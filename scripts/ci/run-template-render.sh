#!/usr/bin/env bash
# scripts/ci/run-template-render.sh — render every *.tmpl with chezmoi
# execute-template, using deterministic fixture values for template variables.
#
# Delegates to tests/integration/chezmoi-render.sh, which is added by Story #27
# and is responsible for setting up a fixture chezmoi source dir (including
# rbw stubs and included asset files) before invoking chezmoi execute-template.
#
# Until #27 lands, emit an empty-but-valid JUnit file and exit 0 — the unit
# and e2e jobs still run and provide signal. This mirrors the graceful-skip
# pattern in run-e2e.sh so the CI pipeline can ship before all dependent
# integration fixtures exist.
set -euo pipefail

mkdir -p tests/results

if [[ -x tests/integration/chezmoi-render.sh ]]; then
    exec tests/integration/chezmoi-render.sh
fi

echo "template-render: tests/integration/chezmoi-render.sh not present (pending Story #27) — skipping" >&2
cat >tests/results/template-render.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="template-render" tests="0" failures="0" errors="0" skipped="0"/>
EOF
exit 0
