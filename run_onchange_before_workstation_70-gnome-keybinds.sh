#!/usr/bin/env bash
# run_onchange_before_workstation_70-gnome-keybinds.sh — register three
# GNOME custom keybindings that launch `cheet-popup.sh` with different
# cheatsheet arguments.
#
# chezmoi `workstation_` prefix: this script is only materialized on hosts
# carrying the workstation tag; server/minimal roles skip it entirely at
# source-tree generation time. No runtime role check needed.
#
# How GNOME custom keybindings work (the part that isn't obvious):
#
#   The list of active custom bindings lives at
#       org.gnome.settings-daemon.plugins.media-keys custom-keybindings
#   as an array of GSettings PATHS (strings), each pointing to a
#   subtree where the binding's (name, command, binding) live:
#       /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/customN/
#
#   Adding a binding is therefore a two-step dance:
#     (1) Write the triple (name/command/binding) at the subtree path.
#     (2) Append the subtree path to the custom-keybindings array if
#         it's not already present. Duplicates → duplicate bindings in
#         Settings > Keyboard > Custom Shortcuts, so uniqueness matters.
#
# Pre-existing-binding safety: we refuse to overwrite a slot whose
# current `name` is non-empty AND different from the beget-chosen
# token we're about to write. We DO overwrite a slot whose name is
# empty (never initialized), AND we DO overwrite a slot whose name
# already equals our own token (idempotent re-run).
# Caveat: a user entry that happens to start with `beget:` is still
# treated as user-owned unless it exactly matches one of the three
# tokens in beget_keybind_table — we compare against the specific
# token, not the `beget:` prefix.
#
# Idempotency: re-running the script produces no change once the three
# bindings are present (same names, commands, keys).
#
# Test seams (env-var overrides):
#   BEGET_GSETTINGS   — gsettings
#   BEGET_DRY_RUN     — "1" to print the gsettings commands without exec

set -euo pipefail

BEGET_GSETTINGS="${BEGET_GSETTINGS:-gsettings}"

# Parent GSettings path for custom-keybindings subtrees.
CUSTOM_KEYS_SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
CUSTOM_KEYS_KEY="custom-keybindings"
CUSTOM_KEYS_PREFIX="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Each binding's subtree uses a beget-scoped schema path to avoid
# colliding with any `customN/` slot GNOME might auto-allocate.
BINDING_SCHEMA="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"

# Name|Command|Shortcut — the three Dev Spec bindings.
# The `name` field is our ownership token; prefix with `beget:` so we
# can detect "already ours" vs "user's own entry" on re-run.
beget_keybind_table() {
    printf '%s\n' \
        "beget:cheet-tldr|cheet-popup.sh tldr|<Primary>F1" \
        "beget:cheet-cheat|cheet-popup.sh cheat|<Alt>F1" \
        "beget:cheet-both|cheet-popup.sh both|<Primary><Alt>F1"
}

# Slugify "beget:cheet-tldr" → "begetcheettldr" for the subtree name.
binding_slug() {
    local name="$1"
    printf '%s' "$name" | tr -cd '[:alnum:]'
}

gset() {
    # Wrapper so dry-run just prints; otherwise exec.
    if [[ "${BEGET_DRY_RUN:-}" == "1" ]]; then
        printf 'gnome-keybinds: DRY-RUN %s %s\n' "$BEGET_GSETTINGS" "$*" >&2
        return 0
    fi
    "$BEGET_GSETTINGS" "$@"
}

get_current_array() {
    # Returns current custom-keybindings array as a raw GSettings literal,
    # e.g. "@as []" or "['/a/', '/b/']". We just pass it back through.
    "$BEGET_GSETTINGS" get "$CUSTOM_KEYS_SCHEMA" "$CUSTOM_KEYS_KEY" 2>/dev/null ||
        printf "@as []"
}

array_contains_path() {
    local arr="$1" path="$2"
    # Literal-substring match is safe because paths end in `/` and are
    # always quoted in the GSettings literal.
    [[ "$arr" == *"'${path}'"* ]]
}

append_path_to_array() {
    local arr="$1" path="$2"
    # Build a new GVariant string. Simple cases:
    #   empty → "['<path>']"
    #   non-empty → "['...', '<path>']"
    local new
    # GSettings emits `@as []` for an empty array-of-strings; tolerate the
    # bare `[]` form and incidental whitespace (e.g. `@as [ ]`) just in case.
    if [[ "$arr" =~ ^@as[[:space:]]*\[[[:space:]]*\]$ || "$arr" =~ ^\[[[:space:]]*\]$ ]]; then
        new="['${path}']"
    else
        # Strip the closing bracket AND any trailing/surrounding whitespace
        # so a stray `['/foo/' ]` form still produces a valid GVariant after
        # append. Without the whitespace strip, `%]` would leave a space
        # before the new comma and emit `['/foo/' , '/bar/']` — parses, but
        # ugly, and a `] ` input would leave the bracket in place and break.
        local stripped
        stripped=$(printf '%s' "$arr" | sed 's/[[:space:]]*][[:space:]]*$//')
        new="${stripped}, '${path}']"
    fi
    gset set "$CUSTOM_KEYS_SCHEMA" "$CUSTOM_KEYS_KEY" "$new"
}

write_binding_triple() {
    local slug="$1" name="$2" command="$3" shortcut="$4"
    local path="${CUSTOM_KEYS_PREFIX}/${slug}/"
    # Use the relocatable-schema-at-path form: `gsettings set <schema>:<path>`
    gset set "${BINDING_SCHEMA}:${path}" name "$name"
    gset set "${BINDING_SCHEMA}:${path}" command "$command"
    gset set "${BINDING_SCHEMA}:${path}" binding "$shortcut"
}

read_binding_name() {
    local path="$1"
    # GSettings emits strings wrapped in single quotes, e.g. 'beget:cheet-tldr'.
    # Strip only the wrapping pair (not embedded apostrophes); `tr -d` would
    # flatten a binding name that legitimately contained "'".
    "$BEGET_GSETTINGS" get "${BINDING_SCHEMA}:${path}" name 2>/dev/null |
        sed "s/^'//; s/'\$//" || printf ''
}

install_binding() {
    local name="$1" command="$2" shortcut="$3"
    local slug
    slug=$(binding_slug "$name")
    local path="${CUSTOM_KEYS_PREFIX}/${slug}/"

    # Guard: refuse to clobber a user-owned slot at our path.
    local existing
    existing=$(read_binding_name "$path" 2>/dev/null || printf '')
    if [[ -n "$existing" && "$existing" != "$name" ]]; then
        printf 'gnome-keybinds: slot %s already owned by %q; skipping\n' \
            "$path" "$existing" >&2
        return 0
    fi

    write_binding_triple "$slug" "$name" "$command" "$shortcut"

    local current
    current=$(get_current_array)
    if array_contains_path "$current" "$path"; then
        printf 'gnome-keybinds: %s already in array, skipping append\n' \
            "$path" >&2
    else
        append_path_to_array "$current" "$path"
    fi
}

main() {
    if ! command -v "$BEGET_GSETTINGS" >/dev/null 2>&1 &&
        [[ "${BEGET_DRY_RUN:-}" != "1" ]]; then
        printf 'gnome-keybinds: %s not on PATH; skipping (non-GNOME host?)\n' \
            "$BEGET_GSETTINGS" >&2
        return 0
    fi

    local name command shortcut
    while IFS='|' read -r name command shortcut; do
        [[ -z "$name" || "${name:0:1}" == "#" ]] && continue
        install_binding "$name" "$command" "$shortcut"
    done < <(beget_keybind_table)
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
