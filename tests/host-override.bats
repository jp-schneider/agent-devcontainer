#!/usr/bin/env bats
# .devcontainer/shared/host-override.sh: WSL detection → compose.host.yml.

load helpers

setup() {
    setup_workdir
    mkdir -p "$WORK/wsl-lib"
    echo "Linux version 6.18.40.1-microsoft-standard-WSL2 (root@host) #1 SMP" > "$WORK/proc-wsl"
    echo "Linux version 6.8.0-45-generic (buildd@lcy02) #45-Ubuntu SMP" > "$WORK/proc-generic"
}

teardown() {
    teardown_workdir
}

# override <proc-version-file> <wsl-lib-dir>: run the script; writes $WORK/out/compose.host.yml
override() {
    run env PROC_VERSION="$1" WSL_LIB_DIR="$2" \
        "$BASH_UNDER_TEST" "$SHARED/host-override.sh" "$WORK/out/compose.host.yml"
}

@test "WSL kernel + WSL libs: mounts /usr/lib/wsl read-only" {
    override "$WORK/proc-wsl" "$WORK/wsl-lib"
    [ "$status" -eq 0 ]
    grep -qF -- '- /usr/lib/wsl:/usr/lib/wsl:ro' "$WORK/out/compose.host.yml"
}

@test "generic kernel: empty overlay" {
    override "$WORK/proc-generic" "$WORK/wsl-lib"
    [ "$status" -eq 0 ]
    grep -qx 'services: {}' "$WORK/out/compose.host.yml"
    not_grep 'usr/lib/wsl' "$WORK/out/compose.host.yml"
}

@test "WSL kernel but no WSL libs dir: empty overlay (no mount of a missing path)" {
    override "$WORK/proc-wsl" "$WORK/does-not-exist"
    [ "$status" -eq 0 ]
    grep -qx 'services: {}' "$WORK/out/compose.host.yml"
}

@test "both overlays parse as compose YAML with a services mapping" {
    for p in proc-wsl proc-generic; do
        override "$WORK/$p" "$WORK/wsl-lib"
        if python3 -c 'import yaml' 2> /dev/null; then py=(python3); else py=(uv run -q --with pyyaml python); fi
        "${py[@]}" -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1])); assert isinstance(d["services"], dict)' \
            "$WORK/out/compose.host.yml"
    done
}
