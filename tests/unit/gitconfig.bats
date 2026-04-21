#!/usr/bin/env bats
# tests/unit/gitconfig.bats — unit tests for git identity dotfiles

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GITCONFIG_TMPL="$REPO_ROOT/dot_gitconfig.tmpl"
    GITCONFIG_ANALOGIC="$REPO_ROOT/dot_gitconfig-analogic"
}

@test "dot_gitconfig.tmpl: exists and is readable" {
    [ -r "$GITCONFIG_TMPL" ]
}

@test "dot_gitconfig-analogic: exists and is readable" {
    [ -r "$GITCONFIG_ANALOGIC" ]
}

@test "dot_gitconfig.tmpl: parseable as a git config file" {
    # `git config -l -f <file>` errors on malformed INI.
    run git config -l -f "$GITCONFIG_TMPL"
    [ "$status" -eq 0 ]
}

@test "dot_gitconfig-analogic: parseable as a git config file" {
    run git config -l -f "$GITCONFIG_ANALOGIC"
    [ "$status" -eq 0 ]
}

@test "dot_gitconfig.tmpl: has personal user.email" {
    run git config -f "$GITCONFIG_TMPL" user.email
    [ "$status" -eq 0 ]
    [ "$output" = "brian@waveeng.com" ]
}

@test "dot_gitconfig.tmpl: has user.name" {
    run git config -f "$GITCONFIG_TMPL" user.name
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "dot_gitconfig.tmpl: declares filter.lfs" {
    run git config -f "$GITCONFIG_TMPL" filter.lfs.required
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "dot_gitconfig.tmpl: contains includeIf for analogicdev (R-24)" {
    run grep -F 'includeIf "hasconfig:remote.*.url:git@gitlab.com:analogicdev/**"' "$GITCONFIG_TMPL"
    [ "$status" -eq 0 ]
}

@test "dot_gitconfig.tmpl: includeIf points at ~/.gitconfig-analogic" {
    # git config exposes the value via the section key.
    local key='includeif.hasconfig:remote.*.url:git@gitlab.com:analogicdev/**.path'
    run git config -f "$GITCONFIG_TMPL" "$key"
    [ "$status" -eq 0 ]
    [ "$output" = "~/.gitconfig-analogic" ]
}

@test "dot_gitconfig-analogic: overrides user.email to Analogic (R-24)" {
    run git config -f "$GITCONFIG_ANALOGIC" user.email
    [ "$status" -eq 0 ]
    [ "$output" = "brbaker@analogic.com" ]
}

@test "dot_gitconfig.tmpl: no credentials/tokens present" {
    # Smoke: any line that looks password/token-shaped is forbidden.
    run grep -iE 'password|token|secret|api[_-]?key' "$GITCONFIG_TMPL"
    [ "$status" -ne 0 ]
}

@test "dot_gitconfig-analogic: no credentials/tokens present" {
    run grep -iE 'password|token|secret|api[_-]?key' "$GITCONFIG_ANALOGIC"
    [ "$status" -ne 0 ]
}
