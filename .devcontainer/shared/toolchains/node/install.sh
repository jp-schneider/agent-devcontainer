#!/usr/bin/env bash
# node toolchain, user-level setup. Runs at image build as the container user.
# Installs fnm only; Node itself is installed per project at container start (post-start.sh) into
# the shared fnm volume, like uv's Python versions.
set -euo pipefail

# fnm, pinned and checksum-verified. To update: the version from
# https://github.com/Schniz/fnm/releases and each asset's sha256 (shown as "digest" in
# https://api.github.com/repos/Schniz/fnm/releases/tags/<version>)
FNM_VERSION=v1.39.0
case "$(uname -m)" in
    x86_64) asset=fnm-linux.zip sha256=7807664f39d39fc518da1c35ba0181e4b3267603c4b1dedeb4b5fc6ae440a224 ;;
    aarch64) asset=fnm-arm64.zip sha256=4eaff58b2c5bf30d0934027572dd0b5bbb60d2a1af309230b53662d4b1d45599 ;;
    *) echo "node toolchain: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
tmp="$(mktemp -d)"
curl -fsSL -o "$tmp/$asset" "https://github.com/Schniz/fnm/releases/download/$FNM_VERSION/$asset"
echo "$sha256  $tmp/$asset" | sha256sum -c -
unzip -q "$tmp/$asset" -d "$tmp"
install -m 755 "$tmp/fnm" "$HOME/.local/bin/fnm"
rm -rf "$tmp"

# Mount points of the node volumes (toolchains/node/compose.yml); created here so fresh named
# volumes inherit the user's ownership
mkdir -p "$HOME/.local/share/fnm" "$HOME/.cache/node"

# pnpm reads its global config from here; the store goes into the shared cache volume (a project
# .npmrc can't carry this: it is masked in the container, see shared/mask-patterns.txt)
mkdir -p "$HOME/.config/pnpm"
echo "store-dir=$HOME/.cache/node/pnpm-store" > "$HOME/.config/pnpm/rc"

# Shell setup, sourced from .bashrc before the interactive guard, so non-interactive shells get it too:
# - the default Node on PATH, a stable path also for processes that don't run fnm's hook
# - fnm's hook: switches Node on `cd` to the version of the nearest .nvmrc/.node-version
cat > "$HOME/.config/node-toolchain.sh" << 'SH'
export FNM_DIR="${FNM_DIR:-$HOME/.local/share/fnm}"
export PATH="$FNM_DIR/aliases/default/bin:$PATH"
if command -v fnm > /dev/null; then
    eval "$(fnm env --use-on-cd --version-file-strategy=recursive --shell bash)"
fi
SH
sed -i '3i source ~/.config/node-toolchain.sh 2>/dev/null || true' "$HOME/.bashrc"
