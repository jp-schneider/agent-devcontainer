#!/usr/bin/env bash
# Symlinks each project's venv dir (any directory under /app containing a
# pyproject.toml) into the persisted virtualenvs volume, so venv contents
# survive container restarts/rebuilds without living on the bind-mounted
# /app. The link name matches $UV_PROJECT_ENVIRONMENT (a relative path,
# e.g. ".venv-nagv2.ct", written per-worktree by toolchains/uv/init-host.sh and passed in by
# toolchains/uv/compose.yml), which uv itself resolves relative to each project's own
# root. Named ".venv-<worktree>.ct" (not ".venv") so it never collides with
# a venv created on the host outside the container, and so each worktree's
# link name stays distinct.
# Idempotent — safe to re-run (e.g. from postStartCommand) as new
# submodules/projects are added.
set -uo pipefail

VENVS_ROOT="${UV_VENVS_ROOT:-/home/vscode/.virtualenvs/default}"
VENV_LINK_NAME="${UV_PROJECT_ENVIRONMENT:-.venv.ct}"
echo "link-venvs: linking project venvs to $VENVS_ROOT (link name $VENV_LINK_NAME)..."
mkdir -p "$VENVS_ROOT"

while IFS= read -r -d '' pyproject; do
    project_dir="$(dirname "$pyproject")"
    rel="${project_dir#/app}"
    rel="${rel#/}"
    slug="${rel:-root}"
    slug="${slug//\//_}"
    target="$VENVS_ROOT/$slug"
    mkdir -p "$target"

    venv_link="$project_dir/$VENV_LINK_NAME"
    if [ -L "$venv_link" ]; then
        continue
    elif [ -e "$venv_link" ]; then
        echo "link-venvs: $venv_link exists and is not a symlink, skipping (move it aside to enable persistence)" >&2
        continue
    fi
    ln -s "$target" "$venv_link"
    echo "link-venvs: linked $venv_link -> $target"
done < <(find /app -name pyproject.toml -not -path "*/.git/*" -not -path "*/node_modules/*" -print0)
