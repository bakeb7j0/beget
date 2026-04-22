#!/usr/bin/env bash
# scripts/ci/run-smoke-canary.sh — real-world canary for the one-liner.
#
# Unlike run-e2e.sh which serves the current working tree over a loopback
# HTTP server (so PR branches can exercise the fetch path), the canary
# hits the REAL GitHub raw URL on `main`. It answers the question
# run-e2e.sh deliberately cannot: "is the live one-liner the world uses
# actually still working?"
#
# Usage: scripts/ci/run-smoke-canary.sh <distro>
# where <distro> matches tests/e2e/Dockerfile.<distro> (ubuntu24|rocky9).
#
# Trigger sources:
#   - .github/workflows/ci.yml post-merge job on push to main
#   - .github/workflows/smoke-canary.yml scheduled daily + workflow_dispatch
#
# Failure policy: this script ALWAYS exits 0. When the canary fails, it
# opens (or comments on) a dedup'd GitHub issue titled
# "smoke: one-liner canary failing on <distro>". That issue IS the
# signal — the job itself stays green so a transient GitHub-raw blip
# doesn't spam required-check churn on every subsequent PR.
set -euo pipefail

distro="${1:?distro argument required (ubuntu24 | rocky9)}"

mkdir -p tests/results
junit_out="tests/results/smoke-canary-${distro}.xml"

dockerfile="tests/e2e/Dockerfile.${distro}"
if [[ ! -f "$dockerfile" ]]; then
    echo "smoke-canary: no Dockerfile.$distro found — skipping" >&2
    cat >"$junit_out" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="smoke-canary-${distro}" tests="0" failures="0" errors="0" skipped="0"/>
EOF
    exit 0
fi

image="beget-e2e:${distro}"
docker build -f "$dockerfile" -t "$image" .

# The bootstrap command the README promises. Runs as the Dockerfile's
# beget user (uid 1000) because install.sh shells out to sudo apt/dnf,
# and sudo needs an /etc/passwd entry matching the runtime uid. Pipe
# to bash -s -- so install.sh parses its flags correctly.
canary_cmd='rm -f /usr/local/bin/chezmoi 2>/dev/null; sudo rm -f /usr/local/bin/chezmoi; curl -fsSL https://raw.githubusercontent.com/bakeb7j0/beget/main/install.sh | bash -s -- --skip-secrets --role=minimal && command -v chezmoi && command -v rbw && command -v direnv'

start=$(date +%s)
canary_log="$(mktemp)"
trap 'rm -f "$canary_log"' EXIT

# No --privileged; match run-e2e.sh's bind-mount + user convention.
# We don't need the host source tree for the canary (the whole point
# is it fetches install.sh from GitHub raw), but bind-mounting /src
# keeps the invocation shape consistent with run-e2e.sh.
canary_status="pass"
canary_failure=""
if ! docker run --rm \
    --user 1000:1000 \
    -e HOME=/home/beget \
    -v "$PWD:/src" \
    -w /src \
    "$image" \
    bash -c "$canary_cmd" >"$canary_log" 2>&1; then
    canary_status="fail"
    canary_failure="canary one-liner failed on ${distro} — see attached log"
    echo "--- canary output (${distro}) ---" >&2
    cat "$canary_log" >&2
fi
duration=$(($(date +%s) - start))

# Emit JUnit with the same shape as run-e2e.sh's per-test fallback.
ts="$(date -u +%Y-%m-%dT%H:%M:%S)"
name="smoke-canary-${distro}"
if [[ "$canary_status" == "pass" ]]; then
    cases='<testcase classname="beget.smoke-canary" name="'"$name"'" time="'"$duration"'"/>'
    failures_attr=0
else
    escaped="${canary_failure//&/\&amp;}"
    escaped="${escaped//</\&lt;}"
    escaped="${escaped//>/\&gt;}"
    escaped="${escaped//\"/\&quot;}"
    cases='<testcase classname="beget.smoke-canary" name="'"$name"'" time="'"$duration"'"><failure message="'"$escaped"'"><![CDATA['"$canary_failure"']]></failure></testcase>'
    failures_attr=1
fi

cat >"$junit_out" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="$name" tests="1" failures="$failures_attr" errors="0" skipped="0" timestamp="$ts">
    $cases
  </testsuite>
</testsuites>
EOF

# File / update a dedup'd GitHub issue on failure. Only runs in a real
# GHA context with a token; a local dev run just prints the log and exits.
if [[ "$canary_status" == "fail" && -n "${GITHUB_ACTIONS:-}" && -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    run_url=""
    if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
        run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    fi
    issue_title="smoke: one-liner canary failing on ${distro}"
    # Dedup: look for any open issue whose title contains both "smoke canary"
    # markers. We search broadly then filter to the exact per-distro title.
    existing_number=""
    if existing_json="$(gh issue list --search "smoke canary" --state open --json number,title 2>/dev/null)"; then
        existing_number="$(printf '%s' "$existing_json" \
            | jq -r --arg t "$issue_title" '.[] | select(.title == $t) | .number' \
            | head -n1)"
    fi
    comment_body="Canary re-failed on \`${distro}\`.

Run: ${run_url:-<unknown>}

Install output (tail):
\`\`\`
$(tail -n 40 "$canary_log" 2>/dev/null || true)
\`\`\`"
    if [[ -n "$existing_number" ]]; then
        gh issue comment "$existing_number" --body "$comment_body" || true
    else
        body="The daily / post-merge smoke canary failed on \`${distro}\`.

This job runs \`scripts/ci/run-smoke-canary.sh ${distro}\`, which pipes
\`https://raw.githubusercontent.com/bakeb7j0/beget/main/install.sh\` to
\`bash -s -- --skip-secrets --role=minimal\` inside a clean ${distro} container.

Failed run: ${run_url:-<unknown>}

Diagnostic steps live in \`docs/runbook.md\` → Troubleshooting → \`smoke: one-liner canary failing\`.

Install output (tail):
\`\`\`
$(tail -n 40 "$canary_log" 2>/dev/null || true)
\`\`\`"
        gh issue create --title "$issue_title" --body "$body" || true
    fi
fi

# Non-blocking: the opened issue is the signal.
exit 0
