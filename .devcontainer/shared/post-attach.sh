#!/usr/bin/env bash
# VS Code attach (postAttachCommand of every variant):
# 1. Warns if the host's VS Code passes git or Docker credentials or the git config into the
#    container. The dev.containers.* settings that prevent it only work as host user settings, so
#    their effects are checked here. The warning goes to stderr and to $warn_file, which every new
#    interactive shell prints (.bashrc, see the Dockerfile); it is recomputed on every attach.
# 2. Removes all credential sections from the user's git config (a copied one may have helpers;
#    the container should use none).
# A failure is reported but doesn't stop the attach.
#
# Env (tests): POST_ATTACH_SYSTEM_GITCONFIG (default /etc/gitconfig), HOME, XDG_CONFIG_HOME
set -uo pipefail

system_gitconfig="${POST_ATTACH_SYSTEM_GITCONFIG:-/etc/gitconfig}"
user_gitconfig="$HOME/.gitconfig"
xdg_gitconfig="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
docker_config="$HOME/.docker/config.json"
warn_file="$HOME/.cache/devcontainer/host-settings-warning"

# --- 1. Checks, before the cleanup changes anything ---
missing=""
if grep -qs 'vscode-remote-containers' "$system_gitconfig" "$user_gitconfig"; then
    missing="$missing  \"dev.containers.gitCredentialHelperConfigLocation\": \"none\"   (git credential helper found)
"
fi
# The image has no ~/.gitconfig and the template never writes one
if [ -f "$user_gitconfig" ]; then
    missing="$missing  \"dev.containers.copyGitConfig\": false   (~/.gitconfig found; if you created it yourself, delete it and use container.env)
"
fi
if grep -qsE '"(credsStore|credHelpers)"' "$docker_config"; then
    missing="$missing  \"dev.containers.dockerCredentialHelper\": false   (Docker credential helper found)
"
fi

if [ -n "$missing" ]; then
    mkdir -p "$(dirname "$warn_file")"
    {
        echo "WARNING: VS Code passes host credentials or config into this container."
        echo "Set in your VS Code user settings on the host, then rebuild the container:"
        printf '%s' "$missing"
        echo "See .devcontainer/CUSTOMIZING.md, \"How do I commit and push?\""
    } > "$warn_file"
    cat "$warn_file" >&2
else
    rm -f "$warn_file"
fi

# --- 2. Remove credential sections (credential, credential.<url>) ---
for f in "$user_gitconfig" "$xdg_gitconfig"; do
    [ -f "$f" ] || continue
    sections="$(git config --file "$f" --name-only --get-regexp '^credential\.' 2>/dev/null \
        | sed 's/\.[^.]*$//' | sort -u)"
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        git config --file "$f" --remove-section "$s" \
            || echo "post-attach: WARNING could not remove [$s] from $f" >&2
    done <<< "$sections"
done
exit 0
