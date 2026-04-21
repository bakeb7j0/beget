#!/usr/bin/env bash
# tests/integration/header-comments.sh — IT-09.
#
# Every run_onchange_* script must begin with:
#   1. A shebang line (#!/usr/bin/env bash or #!/bin/bash) or a chezmoi
#      template preamble for *.tmpl files.
#   2. A comment line naming the script's path.
#   3. At least one comment line describing intent (R-44).
#
# Fails with file:line on first violation per file.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || {
    echo "cannot cd to $REPO_ROOT" >&2
    exit 2
}

shopt -s nullglob
scripts=(run_onchange_*)
if [[ ${#scripts[@]} -eq 0 ]]; then
    echo "header-comments: no run_onchange_* scripts found"
    exit 0
fi

fail=0
for s in "${scripts[@]}"; do
    [[ -f "$s" ]] || continue

    # Pull the first ~20 lines for inspection. Skip chezmoi template
    # preambles ({{- /* ... */ -}} or `{{- if ... -}}`) when present.
    header="$(sed -n '1,20p' "$s")"

    # Check 1: must start with a shebang or a template directive.
    first_line="$(sed -n '1p' "$s")"
    case "$first_line" in
        '#!/usr/bin/env bash' | '#!/bin/bash') ;;
        '{{'*)
            # chezmoi template with Go-template preamble ({{ ... }} or
            # {{- ... -}}); shebang is inside the rendered body, not
            # mandatory on line 1.
            ;;
        *)
            printf '%s:1 FAIL: missing shebang or template preamble\n' "$s" >&2
            fail=1
            continue
            ;;
    esac

    # Check 2: at least one comment line in the first 20 that mentions
    # the file's path (either as written here or the rendered form).
    base_name="$(basename "$s")"
    base_no_tmpl="${base_name%.tmpl}"
    if ! grep -qE "^#.*(${base_name}|${base_no_tmpl})" <<<"$header"; then
        printf '%s:1 FAIL: header does not name the script (%s)\n' \
            "$s" "$base_name" >&2
        fail=1
        continue
    fi

    # Check 3: at least one intent line — a `#` line that is not the
    # shebang, not the filename line, and has substantive text (≥ 10
    # chars after `#`). Signals the script explains why it exists.
    intent_count=0
    while IFS= read -r line; do
        case "$line" in
            '#!'*) continue ;;
            '# '*)
                payload="${line#\# }"
                [[ ${#payload} -ge 10 ]] && intent_count=$((intent_count + 1))
                ;;
        esac
    done <<<"$header"

    if [[ "$intent_count" -lt 2 ]]; then
        printf '%s:1 FAIL: header lacks intent description (R-44)\n' "$s" >&2
        fail=1
    fi
done
exit "$fail"
