#!/usr/bin/env bats
# .devcontainer/shared/protect-paths.sh: generated read-only binds, secret masks, nested-repo abort.

load helpers

setup() {
    setup_workdir
    # Main worktree with an absorbed submodule and some env files
    LIB="$WORK/lib"
    WS="$WORK/main"
    new_repo "$LIB"
    new_repo "$WS"
    git -C "$WS" -c protocol.file.allow=always submodule -q add "$LIB" sub
    git -C "$WS" commit -q -m sub
    echo "SECRET=1" > "$WS/.env"
    echo "X=1" > "$WS/sub/.env.local"
    echo "EX=1" > "$WS/.env.example"
    echo "C=1" > "$WS/container.env"
    G="$WS/.git"
    OUT=".devcontainer/.generated/compose.protect.yml"
}

teardown() {
    teardown_workdir
}

# protect <workspace> [env assignments…]: run the script there; sets $status/$output and $MOUNTS
protect() {
    local ws="$1"
    shift
    cd "$ws"
    run env "$@" "$BASH_UNDER_TEST" "$SHARED/protect-paths.sh" "$OUT"
    MOUNTS=""
    if [ -f "$OUT" ]; then MOUNTS="$(yaml_mounts "$OUT")"; fi
}

# --- A: main worktree

@test "main worktree: succeeds and creates placeholders" {
    protect "$WS"
    [ "$status" -eq 0 ]
    [ -d "$WS/.vscode" ]
    cmp -s "$WS/.claude/settings.json" "$SHARED/claude-settings.default.json"
    grep -qF 'Read(**/.env)' "$WS/.claude/settings.json"
    [ "$(cat "$WS/.claude/settings.local.json")" = "{}" ]
    grep -q mcpServers "$WS/.mcp.json"
}

@test "main worktree: host-trusted workspace paths are read-only" {
    protect "$WS"
    has_mount "ro $WS/.devcontainer -> /app/.devcontainer"
    has_mount "ro $WS/.vscode -> /app/.vscode"
    has_mount "ro $WS/.claude/settings.json -> /app/.claude/settings.json"
    has_mount "ro $WS/.claude/settings.local.json -> /app/.claude/settings.local.json"
    has_mount "ro $WS/.mcp.json -> /app/.mcp.json"
}

@test "main worktree: git hooks/config/modules/worktrees read-only at both container paths, nothing rw" {
    protect "$WS"
    for t in "$G" /app/.git; do
        for x in hooks config modules worktrees; do
            has_mount "ro $G/$x -> $t/$x"
        done
    done
    not_grep '^rw' <<< "$MOUNTS"
}

@test "env files: masked except container.env and .env.example" {
    protect "$WS"
    has_mount "ro /dev/null -> /app/.env"
    has_mount "ro /dev/null -> /app/sub/.env.local"
    not_grep -e '/app/.env.example' -e '/app/container.env' <<< "$MOUNTS"
}

@test "generated files with .env values are masked; resolved-config placeholder is created" {
    mkdir -p "$WS/.devcontainer/shared"
    echo "DEVCONTAINER_X=1" > "$WS/.devcontainer/shared/.env"
    protect "$WS"
    has_mount "ro /dev/null -> /app/.devcontainer/shared/.env"
    has_mount "ro /dev/null -> /app/.devcontainer/.generated/compose.resolved.yml"
    [ -f "$WS/.devcontainer/.generated/compose.resolved.yml" ]
}

# --- B: nested repositories

@test "planted repo dir: aborts, names it, leaves no overlay" {
    git init -q "$WS/planted"
    protect "$WS"
    [ "$status" -ne 0 ]
    output_has "  planted/.git"
    [ ! -e "$WS/$OUT" ]
}

@test "deeply nested planted repo: aborts" {
    mkdir -p "$WS/n/m"
    git init -q "$WS/n/m"
    protect "$WS"
    [ "$status" -ne 0 ]
    output_has "n/m/.git"
}

@test "pointer to a foreign gitdir: aborts" {
    mkdir -p "$WORK/evil" "$WS/p2"
    echo "gitdir: $WORK/evil" > "$WS/p2/.git"
    protect "$WS"
    [ "$status" -ne 0 ]
    output_has "p2/.git"
}

@test "pointer into .git/worktrees: aborts" {
    mkdir -p "$G/worktrees/fake" "$WS/p3"
    echo "gitdir: ../.git/worktrees/fake" > "$WS/p3/.git"
    protect "$WS"
    [ "$status" -ne 0 ]
    output_has "p3/.git"
}

@test "submodule: allowed, its pointer file is read-only" {
    protect "$WS"
    [ "$status" -eq 0 ]
    has_mount "ro $WS/sub/.git -> /app/sub/.git"
}

@test "allowlisted repo dir: allowed and protected like the main repo" {
    git init -q "$WS/planted"
    echo "planted" > "$WS/.devcontainer/allowed-nested-git.txt"
    protect "$WS"
    [ "$status" -eq 0 ]
    for x in hooks config modules worktrees; do
        has_mount "ro $WS/planted/.git/$x -> /app/planted/.git/$x"
    done
}

@test "allowlisted pointer: pointer read-only, its in-workspace gitdir protected" {
    mkdir -p "$WS/gd"
    git init -q --separate-git-dir="$WS/gd/ext" "$WS/ext"
    echo "ext" > "$WS/.devcontainer/allowed-nested-git.txt"
    protect "$WS"
    [ "$status" -eq 0 ]
    has_mount "ro $WS/ext/.git -> /app/ext/.git"
    has_mount "ro $WS/gd/ext/hooks -> /app/gd/ext/hooks"
    has_mount "ro $WS/gd/ext/config -> /app/gd/ext/config"
}

# --- B2: the workspace is a submodule (gitdir in the superproject, relative pointers)

# submodule_ws <superproject-dir> [<nested-path>]: $SUP with the repo $LIB as submodule "proj" (absorbed
# gitdir), which has a nested submodule (default "inner"); sets SUP, B (the workspace), M (its gitdir),
# L (generated links)
submodule_ws() {
    SUP="$1"
    new_repo "$SUP"
    git -C "$LIB" -c protocol.file.allow=always submodule -q add "$WS" "${2:-inner}"
    git -C "$LIB" commit -q -m inner
    git -C "$SUP" -c protocol.file.allow=always submodule -q add "$LIB" proj
    git -C "$SUP" -c protocol.file.allow=always submodule -q update --init --recursive
    B="$SUP/proj"
    M="$SUP/.git/modules/proj"
    L="$B/.devcontainer/.generated/git-links"
    mkdir -p "$B/.devcontainer"
}

@test "submodule workspace: pointer and config replaced, gitdir protected at its own path only" {
    submodule_ws "$WORK/super"
    grep -qx 'gitdir: ../.git/modules/proj' "$B/.git" # the layout this is about
    protect "$B"
    [ "$status" -eq 0 ]
    has_mount "ro $L/1.git -> /app/.git"
    has_mount "ro $L/1.config -> $M/config"
    for x in hooks modules worktrees; do
        has_mount "ro $M/$x -> $M/$x"
    done
    has_mount "ro $M -> /opt/host-gitdir"
    not_grep -- '-> /app/.git/' <<< "$MOUNTS"
    not_grep "$SUP/\.git/config\|-> $SUP/\.git ->" <<< "$MOUNTS"
    not_grep '^rw' <<< "$MOUNTS"
    [ "$(cat "$L/1.git")" = "gitdir: $M" ]
    [ "$(git config -f "$L/1.config" include.path)" = /opt/host-gitdir/config ]
    [ "$(git config -f "$L/1.config" core.worktree)" = /app ]
}

@test "submodule workspace: nested submodule pointer and config relinked" {
    submodule_ws "$WORK/super"
    protect "$B"
    [ "$status" -eq 0 ]
    has_mount "ro $L/2.git -> /app/inner/.git"
    has_mount "ro $L/2.config -> $M/modules/inner/config"
    [ "$(cat "$L/2.git")" = "gitdir: $M/modules/inner" ]
    [ "$(git config -f "$L/2.config" include.path)" = /opt/host-gitdir/modules/inner/config ]
    [ "$(git config -f "$L/2.config" core.worktree)" = /app/inner ]
}

@test "submodule workspace: generated files make git work at another worktree path, host config live" {
    submodule_ws "$WORK/super"
    protect "$B"
    [ "$status" -eq 0 ]
    # What the container sees, with its paths moved under $C: the workspace at $C/app, the gitdir
    # (config replaced by the generated one) and the read-only view of it
    C="$WORK/ctr"
    mkdir -p "$C/app"
    cp -R "$M" "$C/gitdir"
    sed "s|/opt/host-gitdir|$M|; s|= /app|= $C/app|" "$L/1.config" > "$C/gitdir/config"
    echo "gitdir: $C/gitdir" > "$C/app/.git"
    [ "$(git -C "$C/app" rev-parse --show-toplevel)" = "$C/app" ]
    git -C "$B" remote add probe /nonexistent
    git -C "$C/app" remote | grep -qx probe
}

@test "submodule workspace: awkward paths; nested path quoted in the generated config" {
    N='in \"q\" #;x\\y'
    submodule_ws "$WORK/sup 'q' \$HOME" "$N"
    protect "$B"
    [ "$status" -eq 0 ]
    [ "$(cat "$L/1.git")" = "gitdir: $M" ]
    [ "$(cat "$L/2.git")" = "gitdir: $M/modules/$N" ]
    [ "$(git config -f "$L/2.config" core.worktree)" = "/app/$N" ]
    [ "$(git config -f "$L/2.config" include.path)" = "/opt/host-gitdir/modules/$N/config" ]
}

@test "main worktree: no relinked files, no gitdir view" {
    protect "$WS"
    [ "$status" -eq 0 ]
    not_grep 'git-links\|/opt/host-gitdir' <<< "$MOUNTS"
}

# --- C: linked worktree

@test "linked worktree: main gitdir only at its absolute path, own entry rw with ro pointers" {
    git -C "$WS" worktree add -q "$WORK/wt" -b wt
    mkdir -p "$WORK/wt/.devcontainer"
    protect "$WORK/wt"
    [ "$status" -eq 0 ]
    S="$G/worktrees/wt"
    has_mount "ro $G/hooks -> $G/hooks"
    not_grep -- '-> /app/.git/hooks' <<< "$MOUNTS"
    has_mount "rw $S -> $S"
    has_mount "ro $S/commondir -> $S/commondir"
    has_mount "ro $S/gitdir -> $S/gitdir"
    has_mount "ro $S/modules -> $S/modules"
    has_mount "ro $WORK/wt/.git -> /app/.git"
}

# --- D: awkward paths

@test "workspace path with space, \$ and ': escaped for compose and YAML" {
    ODD="$WORK/my proj \$HOME 'q'"
    new_repo "$ODD"
    protect "$ODD"
    [ "$status" -eq 0 ]
    # Raw file: $ doubled (compose escape), ' doubled (YAML single-quoted scalar)
    grep -qF "my proj \$\$HOME ''q''/.devcontainer" "$ODD/$OUT"
    # Parsed YAML: exact path, still with compose's \$\$ (compose unescapes it)
    has_mount "ro $WORK/my proj \$\$HOME 'q'/.devcontainer -> /app/.devcontainer"
}

# --- E: not a git repo

@test "not a git repo: no git mounts" {
    mkdir -p "$WORK/plain/.devcontainer"
    protect "$WORK/plain" GIT_CEILING_DIRECTORIES="$WORK"
    [ "$status" -eq 0 ]
    not_grep '\.git' <<< "$MOUNTS"
}

@test "not a git repo: allowlisted pointer's gitdir is still protected (regression: empty main_git)" {
    P="$WORK/plain2"
    mkdir -p "$P/.devcontainer" "$P/gd"
    (cd "$P" && GIT_CEILING_DIRECTORIES="$WORK" git init -q --separate-git-dir="$P/gd/r" r)
    echo "r" > "$P/.devcontainer/allowed-nested-git.txt"
    protect "$P" GIT_CEILING_DIRECTORIES="$WORK"
    [ "$status" -eq 0 ]
    has_mount "ro $P/gd/r/hooks -> /app/gd/r/hooks"
    has_mount "ro $P/r/.git -> /app/r/.git"
}

# --- F: template development switch

@test "DEVCONTAINER_EDITABLE_BY_AGENT=1: warns, .devcontainer writable, rest still protected" {
    echo "DEVCONTAINER_EDITABLE_BY_AGENT=1" >> "$WS/.env"
    protect "$WS"
    [ "$status" -eq 0 ]
    output_has "WARNING .devcontainer/ is writable"
    not_grep -- '-> /app/.devcontainer$' <<< "$MOUNTS"
    has_mount "ro $G/hooks -> /app/.git/hooks"
    has_mount "ro /dev/null -> /app/.env"
}

@test "DEVCONTAINER_EDITABLE_BY_AGENT=0: .devcontainer protected" {
    echo "DEVCONTAINER_EDITABLE_BY_AGENT=0" >> "$WS/.env"
    protect "$WS"
    has_mount "ro $WS/.devcontainer -> /app/.devcontainer"
}

# --- G: mask patterns

@test "mask patterns: defaults + project additions masked; exceptions and code files not" {
    for f in prod.env keys/server.pem keys/public.pem .npmrc config/secrets.yaml data/token.txt \
        src/secrets.py src/credentials.py .aws/credentials; do
        mkdir -p "$WS/$(dirname "$f")"
        echo x > "$WS/$f"
    done
    printf '%s\n' "# project additions" '^data/token\.txt$' '!^keys/public\.pem$' \
        > "$WS/.devcontainer/mask-patterns.txt"
    protect "$WS"
    [ "$status" -eq 0 ]
    for f in prod.env keys/server.pem .npmrc config/secrets.yaml .aws/credentials data/token.txt; do
        has_mount "ro /dev/null -> /app/$f"
    done
    for f in keys/public.pem src/secrets.py src/credentials.py container.env .env.example; do
        lacks_mount "ro /dev/null -> /app/$f"
    done
}

@test "missing default mask patterns: aborts, leaves no overlay" {
    mkdir -p "$WORK/iso"
    cp "$SHARED/protect-paths.sh" "$WORK/iso/"
    cd "$WS"
    run "$BASH_UNDER_TEST" "$WORK/iso/protect-paths.sh" "$OUT"
    [ "$status" -ne 0 ]
    output_has "mask-patterns.txt is missing"
    [ ! -e "$WS/$OUT" ]
}

# --- Negative control

@test "negative control: has_mount fails for a mount that isn't there" {
    protect "$WS"
    run has_mount "rw $WS/.devcontainer -> /app/.devcontainer"
    [ "$status" -ne 0 ]
}
