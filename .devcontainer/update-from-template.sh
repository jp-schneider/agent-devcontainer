#!/usr/bin/env bash
# Merges updates from the devcontainer template into a repo created from it.
# Keeps this repo's own CLAUDE.md, README.md, .claude/, docs/ and .devcontainer/compose.project.yml,
# and drops the template-only .github/template-cleanup/. Leaves the merge uncommitted for review.
# Run from the repo root on a clean working tree. Bash 3.2 compatible (macOS).
#
# Usage: .devcontainer/update-from-template.sh [<template-url>] [<branch>]
set -euo pipefail

url="${1:-https://github.com/jp-schneider/devcontainer.git}"
branch="${2:-main}"
# Paths owned by this repo, not by the template
own_paths="CLAUDE.md README.md .claude docs .github/template-cleanup .devcontainer/compose.project.yml"

if [ -n "$(git status --porcelain)" ]; then
    echo "update-from-template: working tree not clean, commit or stash first" >&2
    exit 1
fi

git remote get-url template > /dev/null 2>&1 || git remote add template "$url"
git fetch template "$branch"

# The first update has no common history ("Use this template" squashes it)
unrelated=""
if ! git merge-base HEAD "template/$branch" > /dev/null; then
    unrelated="--allow-unrelated-histories"
fi

# Conflicts are expected; own paths are resolved below, the rest is up to the user
git merge --no-commit --no-ff $unrelated "template/$branch" || true

# Only tracked files are touched; untracked/ignored ones (e.g. .claude/settings.local.json) stay
for p in $own_paths; do
    if git cat-file -e "HEAD:$p" 2> /dev/null; then
        # Drop files the template added under our path, then restore ours (also resolves conflicts)
        git diff --cached --name-only --diff-filter=A HEAD -- "$p" | while IFS= read -r f; do
            git rm -q -f -- "$f"
        done
        git checkout HEAD -- "$p"
    else
        # Template-only path
        git rm -r -q -f --ignore-unmatch -- "$p"
    fi
done

conflicts="$(git diff --name-only --diff-filter=U)"
if [ -n "$conflicts" ]; then
    echo "update-from-template: resolve these conflicts, then 'git commit':"
    echo "$conflicts"
else
    echo "update-from-template: merge staged; review with 'git diff --cached', then 'git commit'"
fi
