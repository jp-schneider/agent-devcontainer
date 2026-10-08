#!/usr/bin/env bash
# uv toolchain, user-level setup. Runs at image build as the container user.
set -euo pipefail

# Mount points of the uv volumes (toolchains/uv/compose.yml); created here so
# fresh named volumes inherit the user's ownership
mkdir -p "$HOME/.virtualenvs" "$HOME/.local/share/uv/python"

curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv tool install ruff
uv tool install ty
