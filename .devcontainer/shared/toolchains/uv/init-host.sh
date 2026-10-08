#!/usr/bin/env bash
# uv toolchain, host-side init. Called by initialize.sh from the workspace root.
# Must stay bash 3.2 compatible (macOS system bash).
#
# Usage: init-host.sh <env-file>
set -uo pipefail

env_file="$1"
echo "UV_VENVS_ROOT=/home/vscode/.virtualenvs/$(basename "$PWD")-devcontainer" >> "$env_file"
echo "UV_PROJECT_ENVIRONMENT=.venv-$(basename "$PWD").ct" >> "$env_file"

# Shared across all projects, hence external in compose.yml and created here
# (idempotent) rather than owned by any one compose project
docker volume create claude-code-uv-python-versions > /dev/null
