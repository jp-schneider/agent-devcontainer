#!/usr/bin/env bats
# .devcontainer/shared/initialize.sh end to end, on a throwaway copy of the repo with a fake docker.

load helpers

setup_file() {
    # One copy of the would-be template per file; each test works on its own copy of that
    TEMPLATE_COPY="$BATS_FILE_TMPDIR/template"
    copy_repo "$TEMPLATE_COPY"
    export TEMPLATE_COPY
}

setup() {
    setup_workdir
    fake_docker
    WS="$WORK/myproj"
    cp -R "$TEMPLATE_COPY" "$WS"
    git -C "$WS" init -q
    git -C "$WS" add -A
    git -C "$WS" commit -q -m init
    GEN="$WS/.devcontainer/.generated"
    printf '# project packages\nffmpeg libsm6   libxext6  # OpenCV\n\ncmake=3.28.3-1build7\n' \
        > "$WS/.devcontainer/apt-packages.txt"
    printf 'nvtop # gpu monitoring\n' > "$WS/.devcontainer/python-uv-gpu/apt-packages.txt"
    printf 'cpu-only-pkg\n' > "$WS/.devcontainer/python-uv-cpu/apt-packages.txt"
}

teardown() {
    teardown_workdir
}

# init <variant> [<toolchain>...]
init() {
    cd "$WS"
    run "$BASH_UNDER_TEST" .devcontainer/shared/initialize.sh "$@"
}

apt_list() {
    tr '\n' ' ' < "$GEN/apt-packages.txt"
}

@test "python-uv-gpu: succeeds and writes all generated files" {
    init python-uv-gpu uv
    [ "$status" -eq 0 ]
    [ -f "$GEN/compose.host.yml" ]
    [ -f "$GEN/compose.protect.yml" ]
    grep -q 'resolved: ok' "$GEN/compose.resolved.yml"
    [ -f "$WS/container.env" ]
    [ -f "$WS/.env" ]
}

@test "apt list: project + started variant, comments and blanks stripped, pins kept" {
    init python-uv-gpu uv
    [ "$(apt_list)" = "ffmpeg libsm6 libxext6 cmake=3.28.3-1build7 nvtop " ]
    init python-uv-cpu uv
    [ "$(apt_list)" = "ffmpeg libsm6 libxext6 cmake=3.28.3-1build7 cpu-only-pkg " ]
}

@test "apt list: the shipped project list (comments only) adds no packages" {
    cp "$REPO_ROOT/.devcontainer/apt-packages.txt" "$WS/.devcontainer/apt-packages.txt"
    rm -f "$WS/.devcontainer/python-uv-gpu/apt-packages.txt"
    init python-uv-gpu uv
    [ "$status" -eq 0 ]
    [ ! -s "$GEN/apt-packages.txt" ]
}

@test "apt list: empty file when there are no lists (Dockerfile COPY still works)" {
    rm -f "$WS/.devcontainer/apt-packages.txt" "$WS/.devcontainer/python-uv-gpu/apt-packages.txt"
    init python-uv-gpu uv
    [ "$status" -eq 0 ]
    [ -f "$GEN/apt-packages.txt" ]
    [ ! -s "$GEN/apt-packages.txt" ]
}

@test "shared/.env: generated values; uv toolchain adds UV_* and creates the shared volume" {
    init python-uv-gpu uv
    E="$WS/.devcontainer/shared/.env"
    grep -qx 'PROJECT_SLUG=myproj' "$E"
    grep -qx "LOCAL_WORKSPACE_FOLDER=$WS" "$E"
    grep -qx 'UV_PROJECT_ENVIRONMENT=.venv-myproj.ct' "$E"
    grep -q 'docker volume create claude-code-uv-python-versions' "$WORK/docker.log"
}

@test "base variant (no toolchain): no UV_* and no volume creation" {
    init base
    [ "$status" -eq 0 ]
    not_grep '^UV_' "$WS/.devcontainer/shared/.env"
    not_grep 'volume create' "$WORK/docker.log"
}

@test "template-dev variant: project + its dev packages, no toolchain" {
    init template-dev
    [ "$status" -eq 0 ]
    [ "$(apt_list)" = "ffmpeg libsm6 libxext6 cmake=3.28.3-1build7 shellcheck python3-yaml " ]
    not_grep '^UV_' "$WS/.devcontainer/shared/.env"
}

@test ".env: only DEVCONTAINER_* lines reach compose, unchanged; can't override generated keys" {
    printf '# host config\nDATA_PATH=/home/me/data\nAPI_SECRET=s3cr3t\nDEVCONTAINER_DATA_PATH=/mnt/storage/data\nDEVCONTAINER_LOCAL_WORKSPACE_FOLDER=/evil\n' \
        > "$WS/.env"
    init python-uv-gpu uv
    E="$WS/.devcontainer/shared/.env"
    grep -qx 'DEVCONTAINER_DATA_PATH=/mnt/storage/data' "$E"
    not_grep -e '^DATA_PATH=' -e 's3cr3t' -e 'host config' "$E"
    grep -qx 'DEVCONTAINER_LOCAL_WORKSPACE_FOLDER=/evil' "$E"
    [ "$(grep -c '^LOCAL_WORKSPACE_FOLDER=' "$E")" = 1 ]
    grep -qx "LOCAL_WORKSPACE_FOLDER=$WS" "$E"
}

@test "compose order passed to docker: toolchain, compose.project.yml, then generated" {
    init python-uv-gpu uv
    v=".devcontainer/python-uv-gpu/.."
    grep -qF -- "-f $v/shared/toolchains/uv/compose.yml -f $v/compose.project.yml -f $v/.generated/compose.host.yml -f $v/.generated/compose.protect.yml config" \
        "$WORK/docker.log"
}

@test "resolved config is masked in the protect overlay" {
    init python-uv-gpu uv
    grep -q 'compose.resolved.yml' "$GEN/compose.protect.yml"
}

@test "negative control: a planted repo makes initialize fail" {
    git init -q "$WS/planted"
    init python-uv-gpu uv
    [ "$status" -ne 0 ]
    output_has "ABORT"
}

@test "toolchains: list and resource prefix in shared/.env; mountpoints.txt always written" {
    init python-uv-gpu uv
    E="$WS/.devcontainer/shared/.env"
    grep -qx 'TOOLCHAINS="uv"' "$E"
    grep -qx 'RESOURCE_PREFIX=agent-sandbox' "$E"
    [ -f "$GEN/mountpoints.txt" ]
    [ ! -s "$GEN/mountpoints.txt" ]
    init base
    grep -qx 'TOOLCHAINS=""' "$E"
    [ -f "$GEN/mountpoints.txt" ]
}

@test "toolchains: several run their init-host.sh in the given order" {
    echo '{}' > "$WS/package.json"
    init python-uv-cpu uv node
    [ "$status" -eq 0 ]
    grep -qx 'TOOLCHAINS="uv node"' "$WS/.devcontainer/shared/.env"
    grep -q '^UV_PROJECT_ENVIRONMENT=' "$WS/.devcontainer/shared/.env"
    [ "$(grep 'volume create' "$WORK/docker.log" | cut -d' ' -f4 | tr '\n' ' ')" \
        = "claude-code-uv-python-versions agent-sandbox-node-fnm agent-sandbox-node-cache " ]
    grep -qx '/app/node_modules' "$GEN/mountpoints.txt"
    [ -f "$GEN/compose.node.yml" ]
}

@test "toolchains: warns when a toolchain's compose.yml is not in the variant's compose list" {
    init python-uv-cpu uv node
    output_has "WARNING toolchain node: shared/toolchains/node/compose.yml is not in the dockerComposeFile list of python-uv-cpu"
    case "$output" in *"WARNING toolchain uv"*) false ;; esac
}

@test "toolchains: an unknown toolchain aborts" {
    init python-uv-cpu uv nodee
    [ "$status" -ne 0 ]
    output_has "unknown toolchain 'nodee'"
}
