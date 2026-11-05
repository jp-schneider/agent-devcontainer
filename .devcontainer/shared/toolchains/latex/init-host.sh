#!/usr/bin/env bash
# latex toolchain, host-side init. Called by initialize.sh from the workspace root.
# Must stay bash 3.2 compatible (macOS system bash).
#
# Creates the TeX Live volume, shared across all projects, hence external in compose.yml and
# created here (idempotent).
#
# Usage: init-host.sh <env-file>
set -uo pipefail

env_file="$1"
prefix="$(sed -n 's/^RESOURCE_PREFIX=//p' "$env_file" | tail -n 1)"
prefix="${prefix:-agent-sandbox}"
docker volume create "$prefix-latex-texlive" > /dev/null
