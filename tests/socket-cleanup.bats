#!/usr/bin/env bats
# shared/socket-cleanup.sh: deletes VS Code's relay sockets and the Dev Containers credential helper
# under a fake /tmp, including XDG_RUNTIME_DIR (/tmp/user/<uid>/, depth 3); other files survive.

load helpers

setup() {
    setup_workdir
    T="$WORK/tmp"
    mkdir -p "$T/user/1000/cc-socks" "$T/mcp-x"
}

teardown() {
    teardown_workdir
}

# relays: the files the script must delete, at the depths VS Code uses
relays() {
    printf '%s\n' \
        "$T/vscode-ipc-4c8c41e8.sock" \
        "$T/vscode-ssh-auth-1a2b.sock" \
        "$T/vscode-remote-containers-ipc-046f.sock" \
        "$T/vscode-remote-containers-046f749e.js" \
        "$T/user/1000/vscode-ipc-c6fd438a.sock" \
        "$T/user/1000/vscode-git-03b42282f0.sock" \
        "$T/user/1000/git-graph-askpass-zQn2vHau.sock" \
        "$T/user/1000/vscode-remote-containers-ipc-9f.sock"
}

# others: files that look similar but must survive
others() {
    printf '%s\n' \
        "$T/vscode-wayland-30637bd1.sock" \
        "$T/mcp-x/mcp.sock" \
        "$T/user/1000/cc-socks/41.sock" \
        "$T/user/1000/vscode-git-notes.txt" \
        "$T/vscode-ipc-readme.md"
}

create() {
    local f
    while IFS= read -r f; do : > "$f"; done
}

@test "--once deletes every relay socket and helper, at depth 1 and in /tmp/user/<uid>" {
    relays | create
    others | create
    run "$BASH_UNDER_TEST" "$SHARED/socket-cleanup.sh" --once "$T"
    [ "$status" -eq 0 ]
    local f
    while IFS= read -r f; do
        [ ! -e "$f" ] || { echo "not deleted: $f" >&2; return 1; }
    done < <(relays)
}

@test "negative control: other sockets and look-alike files survive" {
    relays | create
    others | create
    run "$BASH_UNDER_TEST" "$SHARED/socket-cleanup.sh" --once "$T"
    [ "$status" -eq 0 ]
    local f
    while IFS= read -r f; do
        [ -e "$f" ] || { echo "deleted: $f" >&2; return 1; }
    done < <(others)
}

@test "--once succeeds when there is nothing to delete or the dir is missing" {
    run "$BASH_UNDER_TEST" "$SHARED/socket-cleanup.sh" --once "$T"
    [ "$status" -eq 0 ]
    run "$BASH_UNDER_TEST" "$SHARED/socket-cleanup.sh" --once "$WORK/missing"
    [ "$status" -eq 0 ]
}

@test "without --once it keeps cleaning: a socket created later is deleted too" {
    SOCKET_CLEANUP_INTERVAL=0.2 "$BASH_UNDER_TEST" "$SHARED/socket-cleanup.sh" "$T" &
    local pid=$! i
    : > "$T/user/1000/vscode-git-late.sock"
    for i in $(seq 1 50); do
        [ -e "$T/user/1000/vscode-git-late.sock" ] || break
        sleep 0.1
    done
    kill "$pid"
    [ ! -e "$T/user/1000/vscode-git-late.sock" ]
}
