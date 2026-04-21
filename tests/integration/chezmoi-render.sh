#!/usr/bin/env bash
# tests/integration/chezmoi-render.sh -- IT-03.
#
# Render every *.tmpl through `chezmoi execute-template` with the repo
# as chezmoi's source directory (so `include` resolves relatively) and a
# deterministic mock rbw / rbwFields surface so templates that pull
# secrets don't need real Vaultwarden access. Any render error (missing
# fixture, bad template syntax, unresolvable function call) is a
# failure. Reports offending tmpl + the chezmoi error output.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || {
    echo "cannot cd to $REPO_ROOT" >&2
    exit 2
}

if ! command -v chezmoi >/dev/null 2>&1; then
    echo "chezmoi not installed" >&2
    exit 2
fi

# Mock rbw shim -- returns a deterministic JSON blob matching what
# chezmoi's rbw/rbwFields functions feed off. Writes under a scratch
# dir on PATH so the real rbw (if installed) doesn't get invoked.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

cat >"$scratch/rbw" <<'EOF'
#!/usr/bin/env bash
# Mock rbw for chezmoi-render IT-03.
# Usage patterns we must satisfy:
#   rbw get --raw <item>       -> bare secret value
#   rbw get <item>             -> bare secret value (legacy)
#   rbw get --field <f> <item> -> field value
#   rbw --version              -> version string
case "${1:-}" in
    --version) echo "rbw 1.14.0 (mock)"; exit 0 ;;
    get)
        shift
        # Consume --raw / --field <f>
        field=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --raw) shift ;;
                --field) field="$2"; shift 2 ;;
                *) break ;;
            esac
        done
        item="${1:-}"
        if [[ -z "$item" ]]; then exit 1; fi
        # For key-shaped items, emit a JSON object chezmoi rbwFields
        # consumers can traverse. Otherwise emit a plain value.
        case "$item" in
            ssh-id-*)
                # chezmoi's rbwFields converts `fields` array into a
                # map keyed by field.name. The bare privateKey / publicKey
                # keys on the returned map must therefore appear as
                # `fields[]` entries.
                cat <<JSON
{"name":"$item","notes":"","fields":[{"name":"privateKey","value":"-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAMOCK\n-----END OPENSSH PRIVATE KEY-----\n"},{"name":"publicKey","value":"ssh-ed25519 AAAAMOCK $item"}]}
JSON
                ;;
            aws-*)
                # Templates use e.g. `(rbw "aws-default").data.username`;
                # match that shape.
                cat <<JSON
{"name":"$item","notes":"","data":{"username":"AKIAMOCK","password":"SECRETMOCK/AKIAMOCK"},"fields":[]}
JSON
                ;;
            *)
                printf 'mock-value-for-%s\n' "$item"
                ;;
        esac
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$scratch/rbw"

# chezmoi's rbw/rbwFields helpers shell out to the `rbw` binary on
# PATH; put our shim first.
export PATH="$scratch:$PATH"

shopt -s nullglob globstar

# Collect every *.tmpl file the repo ships. Exclude the bats submodule
# and any scratch tree.
mapfile -t templates < <(find . -name '*.tmpl' \
    -not -path './tests/bats/*' \
    -not -path './.git/*' \
    -not -path "$scratch/*" | sort)

if [[ ${#templates[@]} -eq 0 ]]; then
    echo "chezmoi-render: no templates found"
    exit 0
fi

# Use the repo as chezmoi's source dir so include "path" resolves.
export CHEZMOI_SOURCE_DIR="$REPO_ROOT"

fail=0
errlog="$scratch/chezmoi.err"
for tpl in "${templates[@]}"; do
    rel="${tpl#./}"
    if ! chezmoi execute-template --source "$REPO_ROOT" <"$tpl" >/dev/null 2>"$errlog"; then
        printf 'FAIL: %s\n' "$rel" >&2
        sed "s#^#  #" "$errlog" >&2 || true
        fail=1
    fi
done
exit "$fail"
