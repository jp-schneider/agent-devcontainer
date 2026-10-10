#!/usr/bin/env bats
# Invariants across the variants' devcontainer.json (see CONTRIBUTING.md, "Invariants").
# devcontainer.json has no include mechanism, so security settings are duplicated per variant.

load helpers

setup() {
    VARIANTS=""
    for d in "$REPO_ROOT"/.devcontainer/*/; do
        if [ -f "$d/devcontainer.json" ]; then VARIANTS="$VARIANTS $(basename "$d")"; fi
    done
}

# json <variant> <jq filter>: query a variant's devcontainer.json (JSONC: // line comments stripped)
json() {
    sed 's#^\([^"]*\)//.*#\1#' "$REPO_ROOT/.devcontainer/$1/devcontainer.json" | jq -c "$2"
}

# same <jq filter>: the value is identical in every variant
same() {
    local first="" v val
    for v in $VARIANTS; do
        val="$(json "$v" "$1")"
        if [ -z "$first" ]; then
            first="$val"
        elif [ "$val" != "$first" ]; then
            printf '%s differs in %s:\n  %s\nvs\n  %s\n' "$1" "$v" "$val" "$first" >&2
            return 1
        fi
    done
}

@test "there are variants, and every devcontainer.json parses" {
    [ -n "$VARIANTS" ]
    for v in $VARIANTS; do
        json "$v" '.name' > /dev/null
    done
}

@test "remoteEnv is identical in every variant and clears the escape vectors" {
    same '.remoteEnv'
    for v in $VARIANTS; do
        [ "$(json "$v" '.remoteEnv.SSH_AUTH_SOCK')" = '""' ]
        [ "$(json "$v" '.remoteEnv.VSCODE_IPC_HOOK_CLI')" = 'null' ]
        [ "$(json "$v" '.remoteEnv.GIT_ASKPASS')" = 'null' ]
    done
}

@test "VS Code security settings are identical and off" {
    same '.customizations.vscode.settings["dev.containers.dockerCredentialHelper"]'
    same '.customizations.vscode.settings["dev.containers.copyGitConfig"]'
    same '.customizations.vscode.settings["files.exclude"]'
    for v in $VARIANTS; do
        [ "$(json "$v" '.customizations.vscode.settings["dev.containers.dockerCredentialHelper"]')" = false ]
        [ "$(json "$v" '.customizations.vscode.settings["dev.containers.copyGitConfig"]')" = false ]
    done
}

@test "initializeCommand runs shared/initialize.sh with the variant's own folder name" {
    for v in $VARIANTS; do
        [ "$(json "$v" '.initializeCommand[0:3]')" = "[\"bash\",\".devcontainer/shared/initialize.sh\",\"$v\"]" ]
    done
}

@test "compose order: core first, project before the generated files, protect last" {
    for v in $VARIANTS; do
        [ "$(json "$v" '.dockerComposeFile[0]')" = '"../shared/compose.core.yml"' ]
        [ "$(json "$v" '.dockerComposeFile[-1]')" = '"../.generated/compose.protect.yml"' ]
        [ "$(json "$v" '.dockerComposeFile[-2]')" = '"../.generated/compose.host.yml"' ]
        [ "$(json "$v" '.dockerComposeFile[-3]')" = '"../compose.project.yml"' ]
    done
}

@test "postStartCommand keeps the socket cleanup" {
    for v in $VARIANTS; do
        json "$v" '.postStartCommand' | grep -q 'vscode-ssh-auth-'
    done
}

@test "negative control: same() detects a difference" {
    VARIANTS="$VARIANTS"
    json() { case "$1" in "${VARIANTS%% *}") echo a ;; *) echo b ;; esac; }
    VARIANTS="x y"
    run same '.anything'
    [ "$status" -ne 0 ]
}
