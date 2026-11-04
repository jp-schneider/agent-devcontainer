#!/usr/bin/env bats
# Toolchain hooks: shared/post-start.sh (dispatch to each toolchain's post-start.sh) and the node
# toolchain's init-host.sh (package dir discovery, generated overlay, mount points, host dirs);
# the latex toolchain's install.sh and apt list.

load helpers

setup() {
    setup_workdir
    fake_docker
    WS="$WORK/ws"
    GEN="$WS/.devcontainer/.generated"
    mkdir -p "$GEN"
    : > "$GEN/mountpoints.txt"
    printf 'WORKTREE_NAME=ws\nRESOURCE_PREFIX=agent-sandbox\n' > "$WORK/env"
}

teardown() {
    teardown_workdir
}

# node_init: runs the node init-host.sh from the workspace root, like initialize.sh
node_init() {
    cd "$WS"
    run "$BASH_UNDER_TEST" "$SHARED/toolchains/node/init-host.sh" "$WORK/env"
}

pkg() {
    mkdir -p "$WS/$1"
    echo '{}' > "$WS/$1/package.json"
}

@test "post-start: runs each toolchain's hook in DEVCONTAINER_TOOLCHAINS order, past failures" {
    mkdir -p "$WORK/shared/toolchains/a" "$WORK/shared/toolchains/b" "$WORK/shared/toolchains/c"
    cp "$SHARED/post-start.sh" "$WORK/shared/"
    echo 'echo a >> "$LOG"; exit 3' > "$WORK/shared/toolchains/a/post-start.sh"
    echo 'echo c >> "$LOG"' > "$WORK/shared/toolchains/c/post-start.sh"
    export LOG="$WORK/hooks.log"
    DEVCONTAINER_TOOLCHAINS="c b a" run "$BASH_UNDER_TEST" "$WORK/shared/post-start.sh"
    [ "$status" -eq 0 ]
    [ "$(tr '\n' ' ' < "$LOG")" = "c a " ]
    output_has "WARNING a/post-start.sh failed (exit 3)"
}

@test "post-start: no toolchains is a no-op" {
    DEVCONTAINER_TOOLCHAINS="" run "$BASH_UNDER_TEST" "$SHARED/post-start.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "node init-host: creates the shared volumes with the resource prefix" {
    node_init
    [ "$status" -eq 0 ]
    grep -qx 'docker volume create agent-sandbox-node-fnm' "$WORK/docker.log"
    grep -qx 'docker volume create agent-sandbox-node-cache' "$WORK/docker.log"
}

@test "node init-host: no package.json gives an empty overlay and no mount points" {
    node_init
    [ "$status" -eq 0 ]
    grep -qx 'services: {}' "$GEN/compose.node.yml"
    [ ! -s "$GEN/mountpoints.txt" ]
    [ ! -e "$WS/node_modules" ]
}

@test "node init-host: one volume per package dir; skips node_modules and hidden dirs" {
    pkg .
    pkg packages/a
    pkg packages/@scope/b
    pkg node_modules/dep
    pkg packages/a/node_modules/dep
    pkg .next
    pkg .claude/x
    node_init
    [ "$status" -eq 0 ]
    [ "$(tr '\n' ' ' < "$GEN/mountpoints.txt")" \
        = "/app/node_modules /app/packages/@scope/b/node_modules /app/packages/a/node_modules " ]
    Y="$GEN/compose.node.yml"
    grep -qx '        target: /app/node_modules' "$Y"
    grep -qx '        source: nm-packages_-scope_b' "$Y"
    grep -qxF '    name: ${RESOURCE_PREFIX:-agent-sandbox}-${WORKTREE_NAME:-project}-nm-root' "$Y"
    grep -qxF '    name: ${RESOURCE_PREFIX:-agent-sandbox}-${WORKTREE_NAME:-project}-nm-packages_a' "$Y"
    [ "$(grep -c 'type: volume' "$Y")" = 3 ]
    not_grep -e 'dep' -e '\.next' -e '\.claude/' "$Y"
    # Host mount points exist (so Docker doesn't create them root-owned)
    [ -d "$WS/packages/a/node_modules" ]
    [ -d "$WS/packages/@scope/b/node_modules" ]
}

@test "node init-host: the overlay is valid YAML with the expected mounts" {
    if python3 -c 'import yaml' 2> /dev/null; then
        py() { python3 "$@"; }
    elif command -v uv > /dev/null; then
        py() { uv run -q --with pyyaml python "$@"; }
    else
        skip "neither python3 with PyYAML nor uv available"
    fi
    pkg .
    pkg packages/a
    node_init
    run py -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for v in d["services"]["claude-code"]["volumes"]:
    print(v["source"], v["target"], d["volumes"][v["source"]]["name"])' "$GEN/compose.node.yml"
    [ "$status" -eq 0 ]
    output_has 'nm-root /app/node_modules ${RESOURCE_PREFIX:-agent-sandbox}-${WORKTREE_NAME:-project}-nm-root'
    output_has 'nm-packages_a /app/packages/a/node_modules'
}

@test "node init-host: leaves an existing host node_modules alone, skips unsafe paths and symlinks" {
    pkg .
    mkdir -p "$WS/node_modules/hostdep"
    pkg 'with space'
    pkg linked
    ln -s /tmp "$WS/linked/node_modules"
    node_init
    [ "$status" -eq 0 ]
    [ -d "$WS/node_modules/hostdep" ]
    output_has "skipping package dir 'with space'"
    output_has "skipping linked/node_modules"
    [ "$(cat "$GEN/mountpoints.txt")" = "/app/node_modules" ]
}

@test "node init-host: colliding volume names are skipped, not merged" {
    pkg a/b
    pkg a_b
    node_init
    [ "$status" -eq 0 ]
    output_has "volume name nm-a_b already used"
    [ "$(grep -c 'type: volume' "$GEN/compose.node.yml")" = 1 ]
}

# latex_install: runs the latex install.sh as the image build would, with a fake luaotfload-tool
# that exits with $1
latex_install() {
    export HOME="$WORK/home"
    mkdir -p "$HOME" "$WORK/bin"
    printf '#!/bin/sh\necho "$@" >> "%s/luaotfload.log"\nexit %s\n' "$WORK" "$1" > "$WORK/bin/luaotfload-tool"
    chmod +x "$WORK/bin/luaotfload-tool"
    run "$BASH_UNDER_TEST" "$SHARED/toolchains/latex/install.sh"
}

@test "latex install: creates TEXMFHOME and builds the luaotfload font database" {
    latex_install 0
    [ "$status" -eq 0 ]
    [ -d "$WORK/home/texmf/tex/latex" ]
    grep -qx -- '--update' "$WORK/luaotfload.log"
}

@test "latex install: a failing luaotfload-tool warns but doesn't fail the build" {
    latex_install 1
    [ "$status" -eq 0 ]
    output_has "WARNING luaotfload-tool --update failed"
}

@test "latex apt list: parses to package names only, with the tools LaTeX Workshop uses" {
    # Same parsing as the Dockerfile: strip # comments, whitespace-separated
    pkgs=" $(sed 's/#.*//' "$SHARED/toolchains/latex/apt-packages.txt" | tr -s ' \n' '  ') "
    for p in $pkgs; do
        [[ "$p" =~ ^[a-z0-9][a-z0-9.+-]+$ ]] || { echo "not a package name: $p" >&2; false; }
    done
    for p in texlive-latex-extra latexmk biber chktex texlive-extra-utils texlive-luatex texlive-xetex; do
        [[ "$pkgs" == *" $p "* ]] || { echo "missing: $p" >&2; false; }
    done
    # Curated, not the full distribution
    [[ "$pkgs" != *" texlive-full "* ]]
}
