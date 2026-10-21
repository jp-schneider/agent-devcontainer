#!/usr/bin/env bash
# node toolchain, container start (run by shared/post-start.sh). Idempotent, and never fails the
# start: without network, missing Node versions are reported, not installed.
# - Node versions (fnm, in the shared volume mounted at $FNM_DIR): a default (latest LTS) if there
#   is none, plus every version pinned by a .nvmrc / .node-version under /app
# - corepack in every installed version (Node >= 25 no longer bundles it), enabled, so pnpm/yarn
#   follow package.json's "packageManager"
# - node_modules: warns about package dirs without their volume (added since the last rebuild)
#   and about volumes that aren't writable
set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"
export FNM_DIR="${FNM_DIR:-$HOME/.local/share/fnm}"
if ! command -v fnm > /dev/null; then
    echo "node post-start: fnm not found, image built without the node toolchain?" >&2
    exit 1
fi

# Same selection as init-host.sh: directories with a package.json, outside node_modules and hidden dirs
find_pkg_dirs() {
    find /app -mindepth 1 \( -name node_modules -o -name '.*' \) -prune -o -name package.json -type f -print \
        | while IFS= read -r pkg; do dirname "$pkg"; done | LC_ALL=C sort
}

if [ ! -e "$FNM_DIR/aliases/default" ]; then
    echo "node post-start: no default Node yet, installing the latest LTS..."
    # `fnm install --lts` also creates the alias lts-latest
    if fnm install --lts && fnm default lts-latest; then
        echo "node post-start: default Node is $(fnm exec --using=default node --version 2> /dev/null)"
    else
        echo "node post-start: WARNING could not install a default Node (offline?); retried on next start" >&2
    fi
fi

while IFS= read -r version_file; do
    dir="$(dirname "$version_file")"
    # fnm install without a version reads the version file in the current directory; a no-op if
    # that version is installed
    if ! (cd "$dir" && fnm install > /dev/null 2>&1); then
        echo "node post-start: WARNING could not install the Node version of $version_file ($(head -n 1 "$version_file")); offline?" >&2
    fi
done < <(find /app -mindepth 1 \( -name node_modules -o -name '.*' -not -name .nvmrc -not -name .node-version \) -prune \
    -o \( -name .nvmrc -o -name .node-version \) -type f -print)

for bin in "$FNM_DIR"/node-versions/*/installation/bin; do
    [ -x "$bin/node" ] || continue
    if [ ! -e "$bin/corepack" ]; then
        PATH="$bin:$PATH" npm install --global --silent corepack > /dev/null 2>&1 \
            || { echo "node post-start: WARNING could not install corepack into $bin (offline?)" >&2; continue; }
    fi
    if [ ! -e "$bin/pnpm" ]; then
        PATH="$bin:$PATH" corepack enable \
            || echo "node post-start: WARNING corepack enable failed in $bin" >&2
    fi
done

while IFS= read -r dir; do
    nm="$dir/node_modules"
    if ! mountpoint -q "$nm"; then
        echo "node post-start: WARNING $nm has no volume (package dir added since the last build?);" \
            "until you rebuild the container, packages installed here land in the workspace" >&2
    elif [ ! -w "$nm" ]; then
        echo "node post-start: WARNING $nm is not writable: its volume was created before the image had" \
            "this mount point. On the host, remove that volume (name in .devcontainer/.generated/compose.node.yml)" \
            "and rebuild the container" >&2
    fi
done < <(find_pkg_dirs)
exit 0
