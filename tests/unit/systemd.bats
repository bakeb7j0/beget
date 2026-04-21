#!/usr/bin/env bats
# tests/unit/systemd.bats — unit tests for run_onchange_before_40-systemd-user.sh
# and run_onchange_before_41-systemd-system.sh, and the shipped unit files.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    # Scripts live as .sh.tmpl so chezmoi evaluates the
    # {{ include "dot_local/share/beget/systemd/…" | sha256sum }}
    # re-trigger directives. For bats we run them as plain bash — every
    # {{ ... }} line lives inside a `#` comment so bash ignores it.
    USER_SCRIPT="$REPO_ROOT/run_onchange_before_40-systemd-user.sh.tmpl"
    SYS_SCRIPT="$REPO_ROOT/run_onchange_before_41-systemd-system.sh.tmpl"

    export BEGET_SYSTEMD_USER_SRC_DIR="$BATS_TEST_TMPDIR/user-src"
    export BEGET_SYSTEMD_USER_DEST_DIR="$BATS_TEST_TMPDIR/user-dest"
    export BEGET_SYSTEMD_SYS_SRC_DIR="$BATS_TEST_TMPDIR/sys-src"
    export BEGET_SYSTEMD_SYS_DEST_DIR="$BATS_TEST_TMPDIR/sys-dest"
    mkdir -p "$BEGET_SYSTEMD_USER_SRC_DIR" "$BEGET_SYSTEMD_USER_DEST_DIR" \
             "$BEGET_SYSTEMD_SYS_SRC_DIR" "$BEGET_SYSTEMD_SYS_DEST_DIR"

    export BEGET_SUDO="env"
    export BEGET_SYSTEMCTL="$BATS_TEST_TMPDIR/fake-systemctl"
    export SYSTEMCTL_LOG="$BATS_TEST_TMPDIR/systemctl.log"
    : > "$SYSTEMCTL_LOG"
    cat > "$BEGET_SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
echo "SYS:$*" >> "${SYSTEMCTL_LOG}"
EOF
    chmod +x "$BEGET_SYSTEMCTL"
}

# --- shipped unit file content ----------------------------------------------

@test "user unit: gnome-shell-rss-sample.{service,timer} exist and are pairs" {
    local svc="$REPO_ROOT/dot_local/share/beget/systemd/user/gnome-shell-rss-sample.service"
    local tim="$REPO_ROOT/dot_local/share/beget/systemd/user/gnome-shell-rss-sample.timer"
    [ -r "$svc" ]
    [ -r "$tim" ]
    grep -q '^\[Unit\]' "$svc"
    grep -q '^\[Service\]' "$svc"
    grep -q '^\[Install\]' "$svc"
    grep -q '^\[Timer\]' "$tim"
    grep -q 'Unit=gnome-shell-rss-sample.service' "$tim"
}

@test "user unit: restart-xdg-portal is flagged BUG-WORKAROUND" {
    local svc="$REPO_ROOT/dot_local/share/beget/systemd/user/restart-xdg-portal.service"
    local tim="$REPO_ROOT/dot_local/share/beget/systemd/user/restart-xdg-portal.timer"
    [ -r "$svc" ] && [ -r "$tim" ]
    # Prominently = in the header, not buried.
    head -n 10 "$svc" | grep -q 'BUG-WORKAROUND'
    head -n 10 "$tim" | grep -q 'BUG-WORKAROUND'
    # Cite what it does.
    grep -q 'restart xdg-desktop-portal' "$svc"
}

@test "system unit: three .service files exist with [Unit]/[Service]/[Install]" {
    for name in node_exporter ttyd-sesh chronyd; do
        local f="$REPO_ROOT/dot_local/share/beget/systemd/system/${name}.service"
        [ -r "$f" ]
        grep -q '^\[Unit\]' "$f"
        grep -q '^\[Service\]' "$f"
        grep -q '^\[Install\]' "$f"
    done
}

@test "system unit: hardening opts present (NoNewPrivileges, ProtectSystem)" {
    # All three system units ship with baseline hardening.
    for name in node_exporter ttyd-sesh chronyd; do
        local f="$REPO_ROOT/dot_local/share/beget/systemd/system/${name}.service"
        grep -q 'NoNewPrivileges=true' "$f"
        grep -q 'ProtectSystem=' "$f"
    done
}

# --- user script behaviour --------------------------------------------------

stage_user_unit() {
    local name="$1"; local body="$2"
    printf '%s\n' "$body" > "$BEGET_SYSTEMD_USER_SRC_DIR/$name"
}

@test "user script: installs all .service and .timer files to dest" {
    stage_user_unit "a.service" "[Service]"
    stage_user_unit "a.timer"   "[Timer]"
    stage_user_unit "b.timer"   "[Timer]"

    run bash "$USER_SCRIPT"
    [ "$status" -eq 0 ]
    [ -r "$BEGET_SYSTEMD_USER_DEST_DIR/a.service" ]
    [ -r "$BEGET_SYSTEMD_USER_DEST_DIR/a.timer" ]
    [ -r "$BEGET_SYSTEMD_USER_DEST_DIR/b.timer" ]
}

@test "user script: daemon-reload runs exactly once" {
    stage_user_unit "a.timer" "[Timer]"

    run bash "$USER_SCRIPT"
    [ "$status" -eq 0 ]
    # Count daemon-reload invocations.
    local n
    n=$(grep -c 'SYS:--user daemon-reload' "$SYSTEMCTL_LOG" 2>/dev/null || true)
    [ "${n:-0}" = "1" ]
}

@test "user script: enables the two shipped timers" {
    # Stage the real timer filenames our ENABLE_UNITS array targets.
    stage_user_unit "gnome-shell-rss-sample.timer" "[Timer]"
    stage_user_unit "restart-xdg-portal.timer"     "[Timer]"

    run bash "$USER_SCRIPT"
    [ "$status" -eq 0 ]
    grep -q 'SYS:--user enable --now gnome-shell-rss-sample.timer' "$SYSTEMCTL_LOG"
    grep -q 'SYS:--user enable --now restart-xdg-portal.timer' "$SYSTEMCTL_LOG"
}

@test "user script: idempotent — two runs yield identical dest tree" {
    stage_user_unit "a.timer" "[Timer]"

    run bash "$USER_SCRIPT"
    [ "$status" -eq 0 ]
    first=$(find "$BEGET_SYSTEMD_USER_DEST_DIR" -type f -printf '%p %s\n' | sort)

    run bash "$USER_SCRIPT"
    [ "$status" -eq 0 ]
    second=$(find "$BEGET_SYSTEMD_USER_DEST_DIR" -type f -printf '%p %s\n' | sort)
    [ "$first" = "$second" ]
}

@test "user script: BEGET_SKIP_SYSTEMCTL=1 skips daemon-reload and enables" {
    stage_user_unit "a.timer" "[Timer]"

    BEGET_SKIP_SYSTEMCTL=1 run bash "$USER_SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -s "$SYSTEMCTL_LOG" ]
}

@test "user script: missing source dir fails with diagnostic" {
    rm -rf "$BEGET_SYSTEMD_USER_SRC_DIR"
    run bash "$USER_SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"source dir missing"* ]]
}

@test "user script: real shipped unit files install under dest (smoke)" {
    # Wire the shipped chezmoi source dir in place of the staged one.
    # Catches the regression where share/systemd/ was at the wrong chezmoi
    # source path (not under dot_local/...) so BEGET_SYSTEMD_USER_SRC_DIR
    # default of $HOME/.local/share/beget/systemd/user never populated.
    BEGET_SYSTEMD_USER_SRC_DIR="$REPO_ROOT/dot_local/share/beget/systemd/user" \
    BEGET_SKIP_SYSTEMCTL=1 \
        run bash "$USER_SCRIPT"
    [ "$status" -eq 0 ]
    [ -r "$BEGET_SYSTEMD_USER_DEST_DIR/gnome-shell-rss-sample.timer" ]
    [ -r "$BEGET_SYSTEMD_USER_DEST_DIR/restart-xdg-portal.timer" ]
    [ -r "$BEGET_SYSTEMD_USER_DEST_DIR/gnome-shell-rss-sample.service" ]
    [ -r "$BEGET_SYSTEMD_USER_DEST_DIR/restart-xdg-portal.service" ]
}

# --- system script behaviour ------------------------------------------------

stage_sys_unit() {
    local name="$1"; local body="$2"
    printf '%s\n' "$body" > "$BEGET_SYSTEMD_SYS_SRC_DIR/$name"
}

@test "sys script: installs .service files (not .timer) to /etc dest" {
    stage_sys_unit "alpha.service" "[Service]"
    stage_sys_unit "beta.service"  "[Service]"
    # A stray timer should NOT be picked up by the system script.
    stage_sys_unit "ignored.timer" "[Timer]"

    run bash "$SYS_SCRIPT"
    [ "$status" -eq 0 ]
    [ -r "$BEGET_SYSTEMD_SYS_DEST_DIR/alpha.service" ]
    [ -r "$BEGET_SYSTEMD_SYS_DEST_DIR/beta.service" ]
    [ ! -r "$BEGET_SYSTEMD_SYS_DEST_DIR/ignored.timer" ]
}

@test "sys script: daemon-reload runs once, enables the three workstation units" {
    stage_sys_unit "node_exporter.service" "[Service]"
    stage_sys_unit "ttyd-sesh.service"     "[Service]"
    stage_sys_unit "chronyd.service"       "[Service]"

    run bash "$SYS_SCRIPT"
    [ "$status" -eq 0 ]
    local n
    n=$(grep -c 'SYS:daemon-reload' "$SYSTEMCTL_LOG" 2>/dev/null || true)
    [ "${n:-0}" = "1" ]
    grep -q 'SYS:enable --now node_exporter.service' "$SYSTEMCTL_LOG"
    grep -q 'SYS:enable --now ttyd-sesh.service' "$SYSTEMCTL_LOG"
    grep -q 'SYS:enable --now chronyd.service' "$SYSTEMCTL_LOG"
}

@test "sys script: idempotent — two runs yield identical dest tree" {
    stage_sys_unit "alpha.service" "[Service]"

    run bash "$SYS_SCRIPT"
    [ "$status" -eq 0 ]
    first=$(find "$BEGET_SYSTEMD_SYS_DEST_DIR" -type f -printf '%p %s\n' | sort)

    run bash "$SYS_SCRIPT"
    [ "$status" -eq 0 ]
    second=$(find "$BEGET_SYSTEMD_SYS_DEST_DIR" -type f -printf '%p %s\n' | sort)
    [ "$first" = "$second" ]
}

@test "sys script: BEGET_SKIP_SYSTEMCTL=1 skips reload/enable" {
    stage_sys_unit "alpha.service" "[Service]"

    BEGET_SKIP_SYSTEMCTL=1 run bash "$SYS_SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -s "$SYSTEMCTL_LOG" ]
}

@test "sys script: missing source dir fails with diagnostic" {
    rm -rf "$BEGET_SYSTEMD_SYS_SRC_DIR"
    run bash "$SYS_SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"source dir missing"* ]]
}

@test "sys script: real shipped unit files install under dest (smoke)" {
    # Wire the shipped chezmoi source dir in place of the staged one;
    # neutralize sudo since the test installs to $BATS_TEST_TMPDIR.
    BEGET_SYSTEMD_SYS_SRC_DIR="$REPO_ROOT/dot_local/share/beget/systemd/system" \
    BEGET_SUDO="env" \
    BEGET_SKIP_SYSTEMCTL=1 \
        run bash "$SYS_SCRIPT"
    [ "$status" -eq 0 ]
    [ -r "$BEGET_SYSTEMD_SYS_DEST_DIR/node_exporter.service" ]
    [ -r "$BEGET_SYSTEMD_SYS_DEST_DIR/ttyd-sesh.service" ]
    [ -r "$BEGET_SYSTEMD_SYS_DEST_DIR/chronyd.service" ]
}
