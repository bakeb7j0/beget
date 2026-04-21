#!/usr/bin/env bats
# tests/unit/sysctl.bats — unit tests for run_onchange_before_30-sysctl.sh
# and the companion share/sysctl.d/*.conf files.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/run_onchange_before_30-sysctl.sh"

    export BEGET_SYSCTL_SRC_DIR="$BATS_TEST_TMPDIR/src"
    export BEGET_SYSCTL_DEST_DIR="$BATS_TEST_TMPDIR/dest"
    mkdir -p "$BEGET_SYSCTL_SRC_DIR" "$BEGET_SYSCTL_DEST_DIR"

    # Passthrough sudo (cannot use empty — script uses ${BEGET_SUDO:-sudo}).
    export BEGET_SUDO="env"

    # Stub sysctl to log invocations.
    export SYSCTL_LOG="$BATS_TEST_TMPDIR/sysctl.log"
    : > "$SYSCTL_LOG"
    cat > "$BATS_TEST_TMPDIR/fake-sysctl" <<'EOF'
#!/usr/bin/env bash
echo "SYSCTL:$*" >> "${SYSCTL_LOG}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/fake-sysctl"
    export BEGET_SYSCTL="$BATS_TEST_TMPDIR/fake-sysctl"
}

# --- shipped file content ---------------------------------------------------

@test "share/sysctl.d/10-map-count.conf sets vm.max_map_count=1048576" {
    local f="$REPO_ROOT/share/sysctl.d/10-map-count.conf"
    [ -r "$f" ]
    grep -E '^vm\.max_map_count\s*=\s*1048576' "$f"
}

@test "10-map-count.conf contains header comments explaining what/why" {
    local f="$REPO_ROOT/share/sysctl.d/10-map-count.conf"
    # WHAT and WHY markers are required by the Dev Spec AC.
    grep -q '^# WHAT:' "$f"
    grep -q '^# WHY:' "$f"
}

@test "share/sysctl.d/60-carbonyl-userns.conf disables userns restriction" {
    local f="$REPO_ROOT/share/sysctl.d/60-carbonyl-userns.conf"
    [ -r "$f" ]
    grep -E '^kernel\.apparmor_restrict_unprivileged_userns\s*=\s*0' "$f"
}

@test "60-carbonyl-userns.conf contains header comments explaining what/why" {
    local f="$REPO_ROOT/share/sysctl.d/60-carbonyl-userns.conf"
    grep -q '^# WHAT:' "$f"
    grep -q '^# WHY:' "$f"
}

# --- script behaviour -------------------------------------------------------

stage_conf() {
    local name="$1"; local body="$2"
    printf '%s\n' "$body" > "$BEGET_SYSCTL_SRC_DIR/$name"
}

@test "happy path: copies all .conf files and reloads sysctl" {
    stage_conf "10-a.conf" "net.ipv4.tcp_syncookies = 1"
    stage_conf "20-b.conf" "vm.swappiness = 10"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    [ -r "$BEGET_SYSCTL_DEST_DIR/10-a.conf" ]
    [ -r "$BEGET_SYSCTL_DEST_DIR/20-b.conf" ]
    # Exactly one sysctl --system call was emitted.
    local n
    n=$(grep -c 'SYSCTL:--system' "$SYSCTL_LOG" 2>/dev/null || true)
    [ "${n:-0}" = "1" ]
}

@test "installed files have 0644 perms" {
    stage_conf "10-a.conf" "fs.inotify.max_user_watches = 524288"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    local perm
    perm=$(stat -c '%a' "$BEGET_SYSCTL_DEST_DIR/10-a.conf")
    [ "$perm" = "644" ]
}

@test "idempotent: running twice yields identical destination state" {
    stage_conf "10-a.conf" "vm.swappiness = 10"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    first=$(find "$BEGET_SYSCTL_DEST_DIR" -type f -printf '%p %s\n' | sort)

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    second=$(find "$BEGET_SYSCTL_DEST_DIR" -type f -printf '%p %s\n' | sort)

    [ "$first" = "$second" ]
}

@test "BEGET_SKIP_RELOAD=1 skips the sysctl --system reload" {
    stage_conf "10-a.conf" "vm.swappiness = 10"

    BEGET_SKIP_RELOAD=1 run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    [ ! -s "$SYSCTL_LOG" ]
}

@test "missing source dir → non-zero exit with diagnostic" {
    rm -rf "$BEGET_SYSCTL_SRC_DIR"
    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"source dir not found"* ]]
}

@test "empty source dir succeeds with notice and no sysctl reload" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no .conf files found"* ]]
    [ ! -s "$SYSCTL_LOG" ]
}

@test "real shipped files install under dest dir (smoke test)" {
    # Wire the shipped source dir in place of the staged one.
    BEGET_SYSCTL_SRC_DIR="$REPO_ROOT/share/sysctl.d" \
        run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -r "$BEGET_SYSCTL_DEST_DIR/10-map-count.conf" ]
    [ -r "$BEGET_SYSCTL_DEST_DIR/60-carbonyl-userns.conf" ]
}
