#!/usr/bin/env bash
# Merges updates from the devcontainer template into a repo created from it.
# Keeps this repo's own files (see own_paths) and drops template-only ones (docs, policies,
# cleanup). Leaves the merge uncommitted for review.
# Run from the repo root on a clean working tree. Bash 3.2 compatible (macOS).
#
# Usage: .devcontainer/update-from-template.sh [<ref>] [<template-url>]
#   <ref>: a release tag (e.g. v0.2.0) or a branch. Default: the latest vX.Y.Z tag, else main.
set -euo pipefail

ref="${1:-}"
url="${2:-https://github.com/jp-schneider/devcontainer.git}"
# Paths owned by this repo, not by the template (the template's copies are never merged in)
own_paths="CLAUDE.md README.md .claude docs .github/template-cleanup .devcontainer/compose.project.yml
SECURITY.md CONTRIBUTING.md CHANGELOG.md .github/ISSUE_TEMPLATE tests .github/workflows/tests.yml"

if [ -n "$(git status --porcelain)" ]; then
    echo "update-from-template: working tree not clean, commit or stash first" >&2
    exit 1
fi

git remote get-url template > /dev/null 2>&1 || git remote add template "$url"
if [ -z "$ref" ]; then
    ref="$(git ls-remote --tags --refs template 'v*' | sed 's#.*refs/tags/##' \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)" || true
    [ -n "$ref" ] || ref=main
fi
git fetch --no-tags template "$ref"
target="$(git rev-parse 'FETCH_HEAD^{commit}')"

old_version="$(cat .devcontainer/VERSION 2> /dev/null || echo unknown)"
new_version="$(git show "$target:.devcontainer/VERSION" 2> /dev/null || echo unknown)"
echo "update-from-template: $old_version -> $new_version (ref $ref). Changes: https://github.com/jp-schneider/devcontainer/releases"

# The first update has no common history ("Use this template" squashes it)
unrelated=""
if ! git merge-base HEAD "$target" > /dev/null; then
    unrelated="--allow-unrelated-histories"
fi

# Conflicts are expected; own paths are resolved below, the rest is up to the user
git merge --no-commit --no-ff $unrelated -m "Update devcontainer template to $new_version ($ref)" "$target" || true

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

# Template-owned bookkeeping: always the template's version (conflicts on the first, unrelated merge)
for p in .devcontainer/VERSION; do
    if git cat-file -e "$target:$p" 2> /dev/null; then
        git checkout "$target" -- "$p"
    fi
done

conflicts="$(git diff --name-only --diff-filter=U)"
if [ -n "$conflicts" ]; then
    echo "update-from-template: resolve these conflicts, then 'git commit':"
    echo "$conflicts"
else
    echo "update-from-template: merge staged; review with 'git diff --cached', then 'git commit'"
fi
