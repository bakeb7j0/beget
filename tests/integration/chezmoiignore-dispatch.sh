#!/usr/bin/env bash
# tests/integration/chezmoiignore-dispatch.sh -- IT-10.
#
# Verify .chezmoiignore.tmpl gates the OS-specific repo-registration
# scripts correctly. chezmoi reads /etc/os-release at render time from
# the host, so cross-OS verification requires either Docker or a source
# substitution; this test does the latter for speed — substitutes the
# real osRelease.id reference with literal distro ids, then renders.
#
# Checks the actual .chezmoiignore.tmpl file, so a future edit that
# breaks the contract will be caught here before CI even reaches the
# E2E canary that first surfaced the dispatch bug.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPL="$REPO_ROOT/.chezmoiignore.tmpl"

if ! command -v chezmoi >/dev/null 2>&1; then
    echo "chezmoiignore-dispatch: chezmoi not installed" >&2
    exit 2
fi

if [[ ! -f "$TMPL" ]]; then
    echo "chezmoiignore-dispatch: $TMPL not found" >&2
    exit 2
fi

# Baseline: the real template renders on the host without errors. IT-03
# covers this for every *.tmpl; repeated here for clear provenance.
chezmoi execute-template <"$TMPL" >/dev/null

# Swap `.chezmoi.osRelease.id` for a literal and render. Returns the
# resulting ignore list on stdout.
render_for_id() {
    local id="$1"
    sed "s|\.chezmoi\.osRelease\.id|\"$id\"|g" "$TMPL" |
        chezmoi execute-template
}

fail=0
report_fail() {
    echo "FAIL: $1" >&2
    fail=1
}

assert_ignored() {
    local out="$1" file="$2" msg="$3"
    if [[ "$out" != *"$file"* ]]; then
        report_fail "$msg — expected '$file' in ignore list"
        printf '%s\n' "$out" | sed 's/^/    /' >&2
    fi
}

assert_not_ignored() {
    local out="$1" file="$2" msg="$3"
    if [[ "$out" == *"$file"* ]]; then
        report_fail "$msg — did not expect '$file' in ignore list"
        printf '%s\n' "$out" | sed 's/^/    /' >&2
    fi
}

# Debian family: dnf-repos is ignored, apt-repos runs.
for id in ubuntu debian linuxmint pop; do
    out=$(render_for_id "$id")
    assert_not_ignored "$out" "apt-repos" "$id"
    assert_ignored "$out" "dnf-repos" "$id"
done

# RHEL family: apt-repos is ignored, dnf-repos runs.
for id in rhel rocky centos almalinux fedora; do
    out=$(render_for_id "$id")
    assert_ignored "$out" "apt-repos" "$id"
    assert_not_ignored "$out" "dnf-repos" "$id"
done

# Unsupported distro: both ignored — neither apt nor dnf is usable.
out=$(render_for_id "arch")
assert_ignored "$out" "apt-repos" "arch"
assert_ignored "$out" "dnf-repos" "arch"

if [[ $fail -eq 1 ]]; then
    echo "chezmoiignore-dispatch: one or more assertions failed" >&2
    exit 1
fi

echo "chezmoiignore-dispatch: OK"
