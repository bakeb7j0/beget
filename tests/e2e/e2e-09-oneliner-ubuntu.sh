#!/usr/bin/env bash
# tests/e2e/e2e-09-oneliner-ubuntu.sh -- E2E-09.
#
# Requirement: R-01 -- the `curl -fsSL ... | bash` one-liner bootstrap
# path works end-to-end on Ubuntu 24.04. Unlike E2E-01/E2E-02 which
# drive install.sh at the function level in dry-run, this test runs
# install.sh for real against live apt + upstream installers.
#
# To exercise the curl-piped `locate_lib_platform` fallback without
# depending on the PR branch being merged to `main`, we serve the
# repo's current working-tree over a loopback Python http.server and
# set BEGET_RAW_BASE to point curl at it. That way install.sh pulls
# the lib/platform.sh under test, not whatever is at HEAD on GitHub.
#
# The Ubuntu image pre-installs chezmoi; we delete it before running
# so the test exercises the real install_chezmoi path (R-01 coverage
# requires chezmoi be installed by install.sh, not pre-baked).

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

OWNER="bakeb7j0"
REPO_NAME="beget"

# Start a python http.server that binds to an ephemeral port, writes
# the port to a file for the bash caller to read, then serves until
# killed. Uses python's builtin http.server module wrapped so we can
# grab the assigned port without racing the socket bind.
start_http_server() {
    local root="$1"
    local port_file="$2"
    python3 - "$root" "$port_file" <<'PY' &
import sys, os, socketserver
from http.server import SimpleHTTPRequestHandler

root = sys.argv[1]
port_file = sys.argv[2]
os.chdir(root)

class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):  # silence default access log
        pass

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    port = httpd.server_address[1]
    with open(port_file, "w") as fh:
        fh.write(str(port))
    httpd.serve_forever()
PY
    HTTP_PID=$!
}

wait_for_port() {
    local port="$1" tries=0
    while ((tries < 50)); do
        if bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
            exec 3<&- 3>&-
            return 0
        fi
        tries=$((tries + 1))
        sleep 0.1
    done
    return 1
}

# Registered via `trap cleanup EXIT` below — shellcheck can't see the
# dynamic dispatch so it flags every line as unreachable.
# shellcheck disable=SC2317
cleanup() {
    if [[ -n "${HTTP_PID:-}" ]] && kill -0 "$HTTP_PID" 2>/dev/null; then
        kill "$HTTP_PID" 2>/dev/null || true
        wait "$HTTP_PID" 2>/dev/null || true
    fi
    [[ -n "${SERVE_ROOT:-}" && -d "$SERVE_ROOT" ]] && rm -rf "$SERVE_ROOT"
    [[ -n "${PORT_FILE:-}" && -f "$PORT_FILE" ]] && rm -f "$PORT_FILE"
    [[ -n "${INSTALL_LOG:-}" && -f "$INSTALL_LOG" ]] && rm -f "$INSTALL_LOG"
}
trap cleanup EXIT

run_test() {
    # The Ubuntu24 image pre-installs chezmoi at /usr/local/bin/chezmoi
    # so image build stays fast. E2E-09 MUST exercise install.sh's
    # real install_chezmoi path, which short-circuits on
    # `command -v chezmoi`. Scrubbing the physical binary would
    # require root, and the CI runner uses `docker run --user
    # $(id -u):$(id -g)` which maps to a host UID that isn't in the
    # container's /etc/passwd -- so sudo fails with "you do not exist
    # in the passwd database". Instead, drop /usr/local/bin from PATH:
    # curl/git/bash all live in /usr/bin, so install.sh's prereqs are
    # unaffected; the pre-baked chezmoi becomes invisible to
    # `command -v` and install_chezmoi runs its real install flow.
    # install_chezmoi installs to $HOME/.local/bin, which is added to
    # PATH below so the post-conditions can see it.
    export PATH="${HOME}/.local/bin:/usr/bin:/bin"
    hash -r
    if command -v chezmoi >/dev/null 2>&1; then
        _assert_fail "chezmoi still on PATH after scrub: $(command -v chezmoi)"
        return 1
    fi

    # Lay out the loopback root. The server exposes the repo under
    # /bakeb7j0/beget/raw/HEAD/ which mirrors github's raw path
    # shape, so install.sh's fallback URL construction is a
    # pass-through change (prefix swap only).
    SERVE_ROOT="$(mktemp -d)"
    mkdir -p "$SERVE_ROOT/$OWNER/$REPO_NAME/raw"
    ln -s "$REPO" "$SERVE_ROOT/$OWNER/$REPO_NAME/raw/HEAD"

    PORT_FILE="$(mktemp)"
    start_http_server "$SERVE_ROOT" "$PORT_FILE"

    # Wait for the server to write the port file + start accepting.
    local tries=0 port=""
    while ((tries < 50)); do
        if [[ -s "$PORT_FILE" ]]; then
            port="$(cat "$PORT_FILE")"
            break
        fi
        tries=$((tries + 1))
        sleep 0.1
    done
    if [[ -z "$port" ]]; then
        _assert_fail "http server did not report a port within 5s"
        return 1
    fi
    if ! wait_for_port "$port"; then
        _assert_fail "http server bound port $port but did not accept connections"
        return 1
    fi

    local raw_base="http://localhost:${port}/${OWNER}/${REPO_NAME}/raw/HEAD"

    # Smoke-test the server: install.sh must be fetchable.
    if ! curl -fsSL "${raw_base}/install.sh" -o /dev/null; then
        _assert_fail "loopback server did not serve install.sh at ${raw_base}/install.sh"
        return 1
    fi

    # The real bootstrap. Piped through bash so locate_lib_platform
    # hits the curl-download fallback (BASH_SOURCE can't resolve to a
    # file on disk in the piped case).
    #
    # Flag rationale:
    #   --skip-secrets avoids the rbw login prompt.
    #   --role=minimal documents the intended role (chezmoi template
    #     data wiring is a separate piece of work; see install.sh).
    #   --skip-apply narrows the surface to the prereq-install +
    #     chezmoi-init path. The dotfile render pass lives behind its
    #     own E2E (#89); R-01 is just "the bootstrap works".
    #
    # `export` matters: `VAR=val cmd1 | cmd2` scopes the assignment to
    # cmd1 only, so the piped bash subprocess would see an empty
    # BEGET_RAW_BASE and fall back to the real GitHub raw URL --
    # silently defeating the whole loopback-server premise.
    INSTALL_LOG="$(mktemp)"
    export BEGET_RAW_BASE="$raw_base"
    if ! curl -fsSL "${raw_base}/install.sh" |
        bash -s -- --skip-secrets --skip-apply --role=minimal >"$INSTALL_LOG" 2>&1; then
        echo "--- install.sh output ---" >&2
        cat "$INSTALL_LOG" >&2
        _assert_fail "install.sh exited non-zero"
        return 1
    fi

    # Post-conditions. Refresh PATH-cached hashes before `command -v`
    # so freshly-installed binaries are visible in this shell.
    hash -r

    if ! command -v chezmoi >/dev/null 2>&1; then
        _assert_fail "chezmoi not on PATH after install.sh"
        return 1
    fi
    local cm_version
    cm_version="$(chezmoi --version 2>&1 || true)"
    if [[ -z "$cm_version" ]]; then
        _assert_fail "chezmoi --version emitted empty output"
        return 1
    fi

    if ! command -v rbw >/dev/null 2>&1; then
        _assert_fail "rbw not on PATH after install.sh"
        return 1
    fi

    if ! command -v direnv >/dev/null 2>&1; then
        _assert_fail "direnv not on PATH after install.sh"
        return 1
    fi

    # pinentry-curses is the only pinentry install.sh forces (the
    # gnome variant is conditional on XDG_CURRENT_DESKTOP). apt list
    # writes a deprecation notice to stderr that we drop.
    if ! apt list --installed 2>/dev/null | grep -q '^pinentry-curses/'; then
        _assert_fail "pinentry-curses not installed via apt"
        return 1
    fi

    # chezmoi init must have materialized its source state.
    if [[ ! -d "${HOME}/.local/share/chezmoi" ]]; then
        _assert_fail "${HOME}/.local/share/chezmoi does not exist (chezmoi init did not run?)"
        return 1
    fi
}

start=$(date +%s)
failure=""
if ! run_test; then
    failure="assertions failed -- see stderr above"
fi

dur=$(($(date +%s) - start))
if [[ -z "$failure" ]]; then
    echo "E2E-09 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-09 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
