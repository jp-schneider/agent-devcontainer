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

@test "VS Code settings: files.exclude identical, no host-only dev.containers.* settings" {
    same '.customizations.vscode.settings["files.exclude"]'
    # copyGitConfig, gitCredentialHelperConfigLocation, dockerCredentialHelper only work as host user
    # settings; in devcontainer.json they would only suggest a protection (post-attach.sh checks them)
    for v in $VARIANTS; do
        [ "$(json "$v" '[.customizations.vscode.settings | keys[] | select(startswith("dev.containers."))]')" = '[]' ]
    done
}

@test "VS Code relays no host credentials to git, identically in every variant" {
    local k
    for k in github.gitAuthentication git.terminalAuthentication; do
        same ".customizations.vscode.settings[\"$k\"]"
        for v in $VARIANTS; do
            [ "$(json "$v" ".customizations.vscode.settings[\"$k\"]")" = false ]
        done
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

@test "postStartCommand runs the socket cleanup once" {
    for v in $VARIANTS; do
        json "$v" '.postStartCommand' | grep -qF 'bash /app/.devcontainer/shared/socket-cleanup.sh --once'
    done
}

@test "postAttachCommand removes credential helpers from the copied git config" {
    same '.postAttachCommand'
    for v in $VARIANTS; do
        [ "$(json "$v" '.postAttachCommand')" = '"bash /app/.devcontainer/shared/post-attach.sh"' ]
    done
}

@test "the compose command keeps running the socket cleanup in the background" {
    grep -qE '^ *bash /app/\.devcontainer/shared/socket-cleanup\.sh &$' "$SHARED/compose.core.yml"
}

@test "postStartCommand runs the toolchain hooks via shared/post-start.sh" {
    for v in $VARIANTS; do
        json "$v" '.postStartCommand' | grep -qF 'bash /app/.devcontainer/shared/post-start.sh;'
    done
}

@test "every toolchain in initializeCommand has its compose.yml in the compose list" {
    local t
    for v in $VARIANTS; do
        for t in $(json "$v" '.initializeCommand[3:][]' | tr -d '"'); do
            json "$v" '.dockerComposeFile[]' | grep -qxF "\"../shared/toolchains/$t/compose.yml\""
        done
    done
}

@test "template-complete-dev lists every toolchain, each once" {
    local t all="" listed
    for d in "$REPO_ROOT"/.devcontainer/shared/toolchains/*/; do all="$all $(basename "$d")"; done
    listed="$(json template-complete-dev '.initializeCommand[3:][]' | tr -d '"' | tr '\n' ' ')"
    for t in $all; do
        [ "$(tr ' ' '\n' <<< "$listed" | grep -cx "$t")" = 1 ] || { echo "not listed once: $t" >&2; return 1; }
    done
    [ "$(wc -w <<< "$listed")" -eq "$(wc -w <<< "$all")" ]
}

@test "negative control: same() detects a difference" {
    VARIANTS="$VARIANTS"
    json() { case "$1" in "${VARIANTS%% *}") echo a ;; *) echo b ;; esac; }
    VARIANTS="x y"
    run same '.anything'
    [ "$status" -ne 0 ]
}
