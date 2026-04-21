#!/usr/bin/env bats
# tests/unit/gnome-keybinds.bats — unit tests for
# run_onchange_before_workstation_70-gnome-keybinds.sh.
#
# Strategy: stub `gsettings` with a shim that logs every invocation and
# emits a controllable state for `get`. We assert (a) the right schema
# paths are written, (b) the custom-keybindings array gets each path
# exactly once, (c) user-owned slots are not overwritten.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/run_onchange_before_workstation_70-gnome-keybinds.sh"

    export GSETTINGS_LOG="$BATS_TEST_TMPDIR/gsettings.log"
    : > "$GSETTINGS_LOG"
    export BEGET_GSETTINGS="$BATS_TEST_TMPDIR/fake-gsettings"

    # Stateful stub: persist `set <schema> <key> <value>` into a file
    # keyed by "<schema>|<key>" so subsequent `get` calls see the last
    # value written. Empty state reads as `@as []` for arrays and `''`
    # for strings.
    export GSTATE_DIR="$BATS_TEST_TMPDIR/gstate"
    mkdir -p "$GSTATE_DIR"
    cat > "$BEGET_GSETTINGS" <<'EOF'
#!/usr/bin/env bash
echo "GS:$*" >> "$GSETTINGS_LOG"
slug() { printf '%s' "$1" | tr '/:.' '___'; }
case "$1" in
    get)
        schema="$2"; key="$3"
        f="${GSTATE_DIR}/$(slug "$schema")__$(slug "$key")"
        if [[ -r "$f" ]]; then
            cat "$f"
        else
            case "$key" in
                custom-keybindings) printf "@as []\n" ;;
                name|command|binding) printf "''\n" ;;
            esac
        fi
        ;;
    set)
        schema="$2"; key="$3"
        shift 3
        f="${GSTATE_DIR}/$(slug "$schema")__$(slug "$key")"
        printf '%s\n' "$*" > "$f"
        ;;
esac
EOF
    chmod +x "$BEGET_GSETTINGS"
}

@test "keybinds: writes name/command/binding for each of the three bindings" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # Expect one `name` / `command` / `binding` set per binding. The
    # patterns anchor on the trailing-argument position (" name ",
    # " command ", " binding ") to avoid matching the substring
    # "binding" inside the schema path "custom-keybinding".
    local n
    n=$(grep -c '^GS:set .* name ' "$GSETTINGS_LOG" 2>/dev/null || true)
    [ "${n:-0}" = "3" ]
    n=$(grep -c '^GS:set .* command ' "$GSETTINGS_LOG" 2>/dev/null || true)
    [ "${n:-0}" = "3" ]
    n=$(grep -c '^GS:set .* binding ' "$GSETTINGS_LOG" 2>/dev/null || true)
    [ "${n:-0}" = "3" ]
}

@test "keybinds: uses the three Ctrl+F1 / Alt+F1 / Ctrl+Alt+F1 shortcuts" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q '<Primary>F1' "$GSETTINGS_LOG"
    grep -q '<Alt>F1' "$GSETTINGS_LOG"
    grep -q '<Primary><Alt>F1' "$GSETTINGS_LOG"
}

@test "keybinds: passes cheet-popup.sh commands with correct arg" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q 'cheet-popup.sh tldr' "$GSETTINGS_LOG"
    grep -q 'cheet-popup.sh cheat' "$GSETTINGS_LOG"
    grep -q 'cheet-popup.sh both' "$GSETTINGS_LOG"
}

@test "keybinds: appends array with all three subtree paths" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # Each binding triggers one `set custom-keybindings` call.
    local n
    n=$(grep -c 'GS:set org.gnome.settings-daemon.plugins.media-keys custom-keybindings' "$GSETTINGS_LOG" 2>/dev/null || true)
    [ "${n:-0}" = "3" ]
    # And the final call must contain all three paths (string-match).
    grep 'GS:set org.gnome.settings-daemon.plugins.media-keys custom-keybindings' "$GSETTINGS_LOG" \
        | tail -n 1 \
        | grep -q 'begetcheettldr'
    grep 'GS:set org.gnome.settings-daemon.plugins.media-keys custom-keybindings' "$GSETTINGS_LOG" \
        | tail -n 1 \
        | grep -q 'begetcheetcheat'
    grep 'GS:set org.gnome.settings-daemon.plugins.media-keys custom-keybindings' "$GSETTINGS_LOG" \
        | tail -n 1 \
        | grep -q 'begetcheetboth'
}

@test "keybinds: idempotent — re-run with array already containing path does not append duplicate" {
    # Second-run stub: array pre-populated with all three paths.
    cat > "$BEGET_GSETTINGS" <<'EOF'
#!/usr/bin/env bash
echo "GS:$*" >> "$GSETTINGS_LOG"
case "$1" in
    get)
        case "$3" in
            custom-keybindings)
                printf "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/begetcheettldr/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/begetcheetcheat/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/begetcheetboth/']\n"
                ;;
            name) printf "'beget:cheet-tldr'\n" ;;
            command|binding) printf "''\n" ;;
        esac
        ;;
    set) : ;;
esac
EOF
    chmod +x "$BEGET_GSETTINGS"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # No `set custom-keybindings` calls should happen because all paths
    # are already in the array → append is skipped for each binding.
    local n
    n=$(grep -c 'GS:set org.gnome.settings-daemon.plugins.media-keys custom-keybindings' "$GSETTINGS_LOG" 2>/dev/null || true)
    [ "${n:-0}" = "0" ]
}

@test "keybinds: refuses to overwrite a user-owned slot" {
    # Stub: reports a user-owned name at the first slot.
    cat > "$BEGET_GSETTINGS" <<'EOF'
#!/usr/bin/env bash
echo "GS:$*" >> "$GSETTINGS_LOG"
case "$1" in
    get)
        case "$3" in
            custom-keybindings) printf "@as []\n" ;;
            name)
                # Any subtree query → return a USER name (non-beget).
                printf "'user-own-entry'\n"
                ;;
            command|binding) printf "''\n" ;;
        esac
        ;;
    set) : ;;
esac
EOF
    chmod +x "$BEGET_GSETTINGS"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # No name/command/binding writes occurred (all slots are claimed).
    local n
    n=$(grep -c 'GS:set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding' "$GSETTINGS_LOG" 2>/dev/null || true)
    [ "${n:-0}" = "0" ]
    [[ "$output" == *"already owned"* ]]
}

@test "keybinds: no gsettings on PATH → non-gsettings host is skipped cleanly" {
    export BEGET_GSETTINGS="$BATS_TEST_TMPDIR/does-not-exist"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"non-GNOME host"* ]]
}

@test "keybinds: dry-run prints commands without invoking gsettings" {
    # Real-path gsettings but dry-run bypasses exec; the shim should see
    # no invocations at all (dry-run short-circuits before the wrapper).
    cat > "$BEGET_GSETTINGS" <<'EOF'
#!/usr/bin/env bash
# Only answer `get`; any `set` should not happen.
if [[ "$1" == "set" ]]; then
    echo "UNEXPECTED set: $*" >&2
    exit 99
fi
echo "GS:$*" >> "$GSETTINGS_LOG"
case "$3" in
    custom-keybindings) printf "@as []\n" ;;
    *) printf "''\n" ;;
esac
EOF
    chmod +x "$BEGET_GSETTINGS"
    BEGET_DRY_RUN=1 run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # No `set` lines in log (stub would have flagged them as unexpected).
    ! grep -q 'GS:set' "$GSETTINGS_LOG"
    [[ "$output" == *"DRY-RUN"* ]]
}
