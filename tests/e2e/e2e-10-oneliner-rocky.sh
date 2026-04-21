#!/usr/bin/env bash
# tests/e2e/e2e-10-oneliner-rocky.sh -- E2E-10.
#
# Requirement: R-02 -- the `curl -fsSL ... | bash` one-liner bootstrap
# path works end-to-end on Rocky 9. RPM-family counterpart to E2E-09
# (Ubuntu 24.04): same loopback-HTTP + BEGET_RAW_BASE strategy, same
# --skip-apply narrowing, different package manager and different
# distro-specific package names (notably `pinentry` vs
# `pinentry-curses` — the lib/platform.sh::pkg_name_pinentry_tty
# helper is what makes this test pass where a Debian-hardcoded
# constant would fail).
#
# Serving the repo's current working-tree over a loopback Python
# http.server and pointing BEGET_RAW_BASE at it keeps the test
# pre-merge-hermetic: we exercise the install.sh / lib/platform.sh
# under review, not whatever is at HEAD on GitHub.
#
# The Rocky image pre-installs chezmoi at /usr/local/bin; we
# PATH-scrub rather than file-delete (see e2e-09 for rationale: the
# CI runner maps to a host UID not in /etc/passwd, so sudo fails).

set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO/tests/e2e/_lib.sh"

OWNER="bakeb7j0"
REPO_NAME="beget"

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
    def log_message(self, fmt, *args):
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
    # Scrub pre-baked chezmoi out of PATH (see e2e-09 rationale).
    # install_chezmoi / install_direnv install to $HOME/.local/bin;
    # install_rbw uses `cargo install` which lands in
    # $HOME/.cargo/bin. Both dirs are prepended so post-condition
    # `command -v` checks see freshly-installed binaries.
    export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:/usr/bin:/bin"
    hash -r
    if command -v chezmoi >/dev/null 2>&1; then
        _assert_fail "chezmoi still on PATH after scrub: $(command -v chezmoi)"
        return 1
    fi

    SERVE_ROOT="$(mktemp -d)"
    mkdir -p "$SERVE_ROOT/$OWNER/$REPO_NAME/raw"
    ln -s "$REPO" "$SERVE_ROOT/$OWNER/$REPO_NAME/raw/HEAD"

    PORT_FILE="$(mktemp)"
    start_http_server "$SERVE_ROOT" "$PORT_FILE"

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

    if ! curl -fsSL "${raw_base}/install.sh" -o /dev/null; then
        _assert_fail "loopback server did not serve install.sh at ${raw_base}/install.sh"
        return 1
    fi

    # `export` matters: `VAR=val cmd1 | cmd2` scopes the assignment
    # to cmd1 only, so the piped bash subprocess would see an empty
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
    # Pin rbw's install path to prove install_rbw exercised its cargo
    # branch rather than some pre-baked system copy we missed. A future
    # Dockerfile change that pre-installs rbw would otherwise make the
    # `command -v rbw` check above silently vacuous.
    if [[ "$(command -v rbw)" != "${HOME}/.cargo/bin/rbw" ]]; then
        _assert_fail "rbw at unexpected path: $(command -v rbw) (expected ${HOME}/.cargo/bin/rbw)"
        return 1
    fi

    if ! command -v direnv >/dev/null 2>&1; then
        _assert_fail "direnv not on PATH after install.sh"
        return 1
    fi

    # Rocky ships the curses pinentry as plain `pinentry` (no
    # `-curses` suffix — it's the only pinentry variant in the base
    # dnf repos). This is the distro-specific assertion that
    # validates the pkg_name_pinentry_tty() helper: if install.sh
    # tried to `dnf install pinentry-curses` on Rocky, the whole
    # bootstrap would have failed before we got here.
    if ! rpm -q pinentry >/dev/null 2>&1; then
        _assert_fail "pinentry not installed via dnf"
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
    echo "E2E-10 PASS"
    emit_junit pass "$dur"
    exit 0
fi
echo "E2E-10 FAIL: $failure" >&2
emit_junit fail "$dur" "$failure"
exit 1
