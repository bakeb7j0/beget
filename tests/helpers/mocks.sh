#!/usr/bin/env bash
# tests/helpers/mocks.sh — shared test helpers.
#
# Exposes two families of helpers:
#   * make_os_release / reset_os_env — seed a mock /etc/os-release and
#     point platform.sh at it via OS_RELEASE_FILE.
#   * mock_rbw — install a fake `rbw` binary under $BATS_TEST_TMPDIR and
#     point BEGET_RBW_CMD at it. Behaviors: ok | missing | locked |
#     unreachable, matching the categories in dot_bashrc.d/executable_50-wrappers.sh.
#
# Keep this library hermetic — it must never mutate the host. Everything
# lands under $BATS_TEST_TMPDIR which bats cleans up per test.

# make_os_release <id> <version_id> [pretty_name]
# Writes a minimal os-release file to "$BATS_TEST_TMPDIR/os-release" and
# exports OS_RELEASE_FILE to that path.
make_os_release() {
    local id="$1"
    local version_id="$2"
    local pretty_name="${3:-${id} ${version_id}}"

    local tmpdir="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
    local path="${tmpdir}/os-release"

    cat >"$path" <<EOF
NAME="${pretty_name}"
ID=${id}
VERSION_ID="${version_id}"
PRETTY_NAME="${pretty_name}"
EOF

    export OS_RELEASE_FILE="$path"
}

# reset_os_env — clear OS-related env so each test starts fresh.
reset_os_env() {
    unset OS_ID OS_MAJOR_VERSION OS_RELEASE_FILE
}

# mock_rbw <behavior> [value]
# Install a deterministic `rbw` shim under $BATS_TEST_TMPDIR/shim-rbw and
# point BEGET_RBW_CMD at it. Behaviors:
#   ok         — `get` prints <value> (default "secret-value") and exits 0.
#   missing    — `get` exits 1 with "no item" on stderr.
#   locked     — `get` exits 2 with "rbw is locked".
#   unreachable— `get` exits 3 with "network error".
# The shim logs calls to $BATS_TEST_TMPDIR/rbw-calls.log so tests can
# assert on how rbw was invoked.
mock_rbw() {
    local behavior="${1:-ok}"
    local value="${2:-secret-value}"

    local tmpdir="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
    local shim_dir="${tmpdir}/shim-rbw"
    mkdir -p "$shim_dir"

    local shim_path="${shim_dir}/rbw"
    local log_path="${tmpdir}/rbw-calls.log"
    : >"$log_path"

    export BEGET_RBW_CMD="$shim_path"
    export MOCK_RBW_LOG="$log_path"

    cat >"$shim_path" <<EOF
#!/usr/bin/env bash
# Mock rbw installed by tests/helpers/mocks.sh::mock_rbw.
printf '%s\n' "\$*" >>"$log_path"
sub="\${1:-}"
item="\${2:-}"
case "\$sub" in
  get)
    case "$behavior" in
      ok)          printf '%s' '$value'; exit 0 ;;
      missing)     echo "rbw get: no item named \$item" >&2; exit 1 ;;
      locked)      echo "rbw is locked" >&2; exit 2 ;;
      unreachable) echo "rbw: network error" >&2; exit 3 ;;
    esac
    ;;
  add)
    value_in="\$(cat)"
    printf 'add %s value=%s\n' "\$item" "\$value_in" >>"$log_path"
    case "$behavior" in
      ok)      exit 0 ;;
      missing) echo "rbw add: synthetic failure" >&2; exit 1 ;;
      *)       exit 0 ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
EOF
    chmod +x "$shim_path"
}
