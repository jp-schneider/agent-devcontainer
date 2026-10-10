#!/usr/bin/env bash
# Runs the template's test suites with bats-core.
#
# bats is a dev dependency, pinned here: `bats` from PATH is used if present (unless
# BATS_PINNED=1), otherwise bats-core $BATS_VERSION is downloaded once into a cache **outside the
# workspace** and checked against $BATS_COMMIT. (A clone inside the workspace would be a nested
# repo, which aborts the next container start; a submodule can't be initialised in the container.)
#
# Usage: tests/run.sh [bats args]          e.g. tests/run.sh tests/protect-paths.bats
# Env:   BASH_UNDER_TEST=/bin/bash        run the scripts under test with that bash (macOS: 3.2)
#        BATS_PINNED=1                    ignore a bats from PATH, use the pinned version
set -euo pipefail

BATS_VERSION=v1.14.0
BATS_COMMIT=eb7f42f8d608ac693d7a4b67474f6714ea68cfc5

root="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ -z "${BATS_PINNED:-}" ] && command -v bats > /dev/null 2>&1; then
    bats=bats
else
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/devcontainer-template/bats-core-$BATS_VERSION"
    case "$cache" in
        "$root" | "$root"/*)
            echo "run.sh: the bats cache must be outside the workspace ($cache)" >&2
            exit 1
            ;;
    esac
    if [ ! -x "$cache/bin/bats" ]; then
        echo "run.sh: fetching bats-core $BATS_VERSION ($BATS_COMMIT)" >&2
        tmp="$(mktemp -d)"
        git clone --quiet --depth 1 --branch "$BATS_VERSION" \
            https://github.com/bats-core/bats-core.git "$tmp/bats-core" 2> /dev/null
        actual="$(git -C "$tmp/bats-core" rev-parse HEAD)"
        if [ "$actual" != "$BATS_COMMIT" ]; then
            echo "run.sh: bats-core $BATS_VERSION is $actual, expected $BATS_COMMIT; refusing to run it" >&2
            rm -rf "$tmp"
            exit 1
        fi
        rm -rf "$tmp/bats-core/.git"
        mkdir -p "$(dirname "$cache")"
        rm -rf "$cache"
        mv "$tmp/bats-core" "$cache"
        rm -rf "$tmp"
    fi
    bats="$cache/bin/bats"
fi

cd "$root"
[ $# -gt 0 ] || set -- tests
exec "$bats" "$@"
