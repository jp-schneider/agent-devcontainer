#!/usr/bin/env bash
# Deletes the sockets and helper scripts through which VS Code relays requests from the container
# to the host: IPC (runs `code` commands on the host), Git askpass and the Dev Containers credential
# helper (answer git with the host's credentials), SSH agent forwarding.
#
# A second layer: the VS Code settings in devcontainer.json turn the credential relays off. VS Code
# recreates the sockets on every attach, hence the loop.
#
# Usage: socket-cleanup.sh [--once] [<dir>]
#   --once  clean once (postStartCommand); default: every SOCKET_CLEANUP_INTERVAL seconds (5), forever
#   <dir>   where to look (default /tmp; tests pass their own). Depth 3 reaches
#           XDG_RUNTIME_DIR=/tmp/user/<uid>/, where VS Code puts most of them.
set -u

once=0
if [ "${1:-}" = "--once" ]; then
    once=1
    shift
fi
dir="${1:-/tmp}"
interval="${SOCKET_CLEANUP_INTERVAL:-5}"

clean() {
    find "$dir" -maxdepth 3 \( \
        -name 'vscode-ipc-*.sock' \
        -o -name 'vscode-git-*.sock' \
        -o -name 'git-graph-askpass-*.sock' \
        -o -name 'vscode-ssh-auth-*.sock' \
        -o -name 'vscode-remote-containers-ipc-*.sock' \
        -o -name 'vscode-remote-containers-*.js' \
        \) -delete 2>/dev/null || true
}

clean
[ "$once" = 1 ] && exit 0
while sleep "$interval"; do
    clean
done
