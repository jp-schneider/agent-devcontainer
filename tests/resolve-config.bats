#!/usr/bin/env bats
# .devcontainer/shared/resolve-config.sh: compose file list from each variant, failure handling.

load helpers

setup() {
    setup_workdir
    fake_docker
}

teardown() {
    teardown_workdir
}

# resolve <variant> <out>: run from the repo root (reads only; writes to <out>)
resolve() {
    cd "$REPO_ROOT"
    run "$BASH_UNDER_TEST" .devcontainer/shared/resolve-config.sh "$@"
}

variants() {
    for d in "$REPO_ROOT"/.devcontainer/*/; do
        if [ -f "$d/devcontainer.json" ]; then basename "$d"; fi
    done
}

@test "every variant: header written; compose order core … project … host, protect last, then config" {
    [ -n "$(variants)" ]
    for v in $(variants); do
        resolve "$v" "$WORK/$v.yml"
        [ "$status" -eq 0 ]
        head -n 1 "$WORK/$v.yml" | grep -q "variant $v"
        args="$(grep "compose -f .devcontainer/$v/" "$WORK/docker.log" | tail -n 1)"
        case "$args" in
            "docker compose -f .devcontainer/$v/../shared/compose.core.yml "*) ;;
            *) echo "core not first for $v: $args" >&2; return 1 ;;
        esac
        case "$args" in
            *"-f .devcontainer/$v/../compose.project.yml -f .devcontainer/$v/../.generated/compose.host.yml -f .devcontainer/$v/../.generated/compose.protect.yml config") ;;
            *) echo "wrong tail order for $v: $args" >&2; return 1 ;;
        esac
    done
}

@test "only GPU variants get the GPU overlay" {
    for v in $(variants); do
        resolve "$v" "$WORK/$v.yml"
        case "$v" in
            *gpu*) grep -q 'compose.gpu.yml' "$WORK/docker.log" ;;
            *) grep "compose -f .devcontainer/$v/" "$WORK/docker.log" | not_grep 'compose.gpu.yml' ;;
        esac
        : > "$WORK/docker.log"
    done
}

@test "docker failure: warns with compose's error, writes nothing, leaves no temp files" {
    FAKE_DOCKER_FAIL=1 resolve python-uv-gpu "$WORK/fail.yml"
    [ "$status" -eq 0 ]
    output_has "WARNING 'docker compose config' failed"
    output_has "fake failure"
    [ ! -e "$WORK/fail.yml" ]
    [ ! -e "$WORK/fail.yml.tmp" ]
    [ ! -e "$WORK/fail.yml.err" ]
}

@test "unknown variant: warns, writes nothing" {
    resolve no-such-variant "$WORK/x.yml"
    [ "$status" -eq 0 ]
    output_has "not found, skipping"
    [ ! -e "$WORK/x.yml" ]
}

@test "negative control: devcontainer.json without dockerComposeFile warns, writes nothing" {
    mkdir -p "$WORK/ws2/.devcontainer/v"
    echo '{ "name": "x", "image": "ubuntu" }' > "$WORK/ws2/.devcontainer/v/devcontainer.json"
    cd "$WORK/ws2"
    run "$BASH_UNDER_TEST" "$SHARED/resolve-config.sh" v "$WORK/v.yml"
    [ "$status" -eq 0 ]
    output_has "no dockerComposeFile entries"
    [ ! -e "$WORK/v.yml" ]
}
