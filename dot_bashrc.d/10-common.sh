# ~/.bashrc.d/10-common.sh — managed by chezmoi via beget
#
# Shared interactive-shell bootstrap. Runs after the main ~/.bashrc has
# loaded aliases and history. Idempotent — safe to re-source.
#
# Load order convention: 10 (common) → 50 (secret wrappers, added later) → 90.

# ---- PATH -------------------------------------------------------------------
# R-39: $HOME/.local/bin precedes /usr/bin and /usr/local/bin. Prepend in
# reverse order so the final PATH reads ~/.local/bin : ~/.cargo/bin : original.

_beget_path_prepend() {
    local dir="$1"
    case ":$PATH:" in
        *":$dir:"*) return 0 ;;
    esac
    if [ -d "$dir" ]; then
        PATH="$dir:$PATH"
    fi
}

_beget_path_prepend "$HOME/.cargo/bin"
_beget_path_prepend "$HOME/.local/bin"
export PATH

# ---- zoxide ------------------------------------------------------------------
# Smarter `cd`. Registers the `z` command; silently skipped if zoxide is not
# installed on this host.
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
fi

# ---- fzf ---------------------------------------------------------------------
# Fuzzy finder key bindings + completion. Ships either as /usr/share/fzf on
# Debian/Ubuntu or under ~/.fzf.bash depending on install method.
if [ -r /usr/share/doc/fzf/examples/key-bindings.bash ]; then
    # shellcheck source=/dev/null
    . /usr/share/doc/fzf/examples/key-bindings.bash
fi
if [ -r /usr/share/bash-completion/completions/fzf ]; then
    # shellcheck source=/dev/null
    . /usr/share/bash-completion/completions/fzf
elif [ -r "$HOME/.fzf.bash" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.fzf.bash"
fi

# ---- direnv ------------------------------------------------------------------
# Per-directory env management. Placeholder hook — the full wiring lands in
# the direnv wave; this guards against a missing binary cleanly.
if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook bash)"
fi
