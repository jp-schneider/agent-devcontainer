#!/usr/bin/env bash
# Symlinks each project's venv dir (any directory under /app containing a
# pyproject.toml) into the persisted virtualenvs volume, so venv contents
# survive container restarts/rebuilds without living on the bind-mounted
# /app. The link name matches $UV_PROJECT_ENVIRONMENT (a relative path,
# e.g. ".venv-nagv2.ct", written per-worktree into .devcontainer/shared/.env by
# toolchains/uv/init-host.sh), which uv itself resolves relative to each project's own
# root. Named ".venv-<worktree>.ct" (not ".venv") so it never collides with
# a venv created on the host outside the container, and so each worktree's
# link name stays distinct.
# Idempotent — safe to re-run (e.g. from postStartCommand) as new
# submodules/projects are added.
set -uo pipefail

# env_file/environment values in the compose files are baked into the
# container at creation time, not re-applied on every start — so if
# init-host.sh regenerates .devcontainer/shared/.env after the container already
# exists (e.g. a plain start/resume rather than a recreate), the inherited
# environment here can be stale. /app is bind-mounted, so re-source the
# live files directly to always pick up the current values.
for env_file in /app/.env /app/.devcontainer/shared/.env; do
    if [ -f "$env_file" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    fi
done

echo "link-venvs: linking project venvs to $UV_VENVS_ROOT (link name $UV_PROJECT_ENVIRONMENT)..."

VENVS_ROOT="${UV_VENVS_ROOT:-/home/vscode/.virtualenvs/default}"
VENV_LINK_NAME="${UV_PROJECT_ENVIRONMENT:-.venv.ct}"
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
