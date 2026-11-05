#!/usr/bin/env bats
# shared/post-attach.sh in a fake $HOME:
# - warns (stderr + warning file) for each host setting whose effect is visible: VS Code's git
#   credential helper, a copied ~/.gitconfig, a Docker credential helper; no warning file otherwise;
# - removes every credential section (plain and per-URL) from ~/.gitconfig and the XDG git config,
#   other settings stay.

load helpers

setup() {
    setup_workdir
    export HOME="$WORK/home" XDG_CONFIG_HOME=""
    export POST_ATTACH_SYSTEM_GITCONFIG="$WORK/etc-gitconfig"
    mkdir -p "$HOME"
    : > "$POST_ATTACH_SYSTEM_GITCONFIG"
    W="$HOME/.cache/devcontainer/host-settings-warning"
}

teardown() {
    teardown_workdir
}

# copied_gitconfig <file>: a host git config as VS Code copies it
copied_gitconfig() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<'EOF'
[user]
	name = Test User
	email = test@example.com
[credential]
	gitHubAccountFiltering = false
	helper = store
[credential "https://github.com"]
	helper = !gh auth git-credential
	username = someone
[init]
	defaultBranch = main
EOF
}

attach() {
    run "$BASH_UNDER_TEST" "$SHARED/post-attach.sh"
}

@test "clean container: no warning, no warning file" {
    attach
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -e "$W" ]
}

@test "removes plain and per-URL credential sections from ~/.gitconfig and the XDG config" {
    copied_gitconfig "$HOME/.gitconfig"
    copied_gitconfig "$HOME/.config/git/config"
    attach
    [ "$status" -eq 0 ]
    run git config --file "$HOME/.gitconfig" --get-regexp '^credential\.'
    [ "$status" -eq 1 ]
    run git config --file "$HOME/.config/git/config" --get-regexp '^credential\.'
    [ "$status" -eq 1 ]
}

@test "negative control: other settings stay" {
    copied_gitconfig "$HOME/.gitconfig"
    attach
    [ "$status" -eq 0 ]
    [ "$(git config --file "$HOME/.gitconfig" user.name)" = "Test User" ]
    [ "$(git config --file "$HOME/.gitconfig" init.defaultBranch)" = "main" ]
}

@test "a copied ~/.gitconfig warns about copyGitConfig, on stderr and in the warning file" {
    printf '[user]\n\tname = x\n' > "$HOME/.gitconfig"
    attach
    [ "$status" -eq 0 ]
    output_has 'dev.containers.copyGitConfig'
    grep -qF 'dev.containers.copyGitConfig' "$W"
    ! grep -qF 'gitCredentialHelperConfigLocation' "$W" || return 1
    ! grep -qF 'dockerCredentialHelper' "$W" || return 1
}

@test "VS Code's credential helper in the system config warns about gitCredentialHelperConfigLocation" {
    printf '[credential]\n\thelper = "!f() { node /tmp/vscode-remote-containers-1.js git-credential-helper $*; }; f"\n' \
        > "$POST_ATTACH_SYSTEM_GITCONFIG"
    attach
    [ "$status" -eq 0 ]
    grep -qF '"dev.containers.gitCredentialHelperConfigLocation": "none"' "$W"
    ! grep -qF 'copyGitConfig' "$W" || return 1
}

@test "a Docker credential helper warns about dockerCredentialHelper" {
    mkdir -p "$HOME/.docker"
    printf '{\n  "credsStore": "dev-containers-abc"\n}\n' > "$HOME/.docker/config.json"
    attach
    [ "$status" -eq 0 ]
    grep -qF '"dev.containers.dockerCredentialHelper": false' "$W"
}

@test "the warning file is removed once the cause is gone" {
    printf '[user]\n\tname = x\n' > "$HOME/.gitconfig"
    attach
    [ -s "$W" ]
    rm "$HOME/.gitconfig"
    attach
    [ "$status" -eq 0 ]
    [ ! -e "$W" ]
}

# bashrc_line: the warning line the Dockerfile appends to ~/.bashrc, as it ends up there
bashrc_line() {
    grep -F 'host-settings-warning' "$SHARED/Dockerfile" | grep -F 'case $- in' \
        | sed "s/^.*echo '\(.*\)' >> ~\/.bashrc.*$/\1/"
}

@test "the Dockerfile's .bashrc line prints the warning in interactive shells only" {
    bashrc_line > "$WORK/bashrc"
    [ -s "$WORK/bashrc" ]
    mkdir -p "$(dirname "$W")"
    echo "WARN-MARKER" > "$W"
    run bash --rcfile "$WORK/bashrc" -i < /dev/null
    output_has "WARN-MARKER"
    run env BASH_ENV="$WORK/bashrc" bash -c true
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "the .bashrc line is quiet without a warning file" {
    bashrc_line > "$WORK/bashrc"
    run bash --rcfile "$WORK/bashrc" -i < /dev/null
    [ "$status" -eq 0 ]
    case "$output" in *WARNING*) return 1 ;; esac
}
