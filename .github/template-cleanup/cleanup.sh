#!/usr/bin/env bash
# One-time reset after "Use this template": replaces the template's own CLAUDE.md,
# README.md and .claude/ history with fresh project files, then deletes this
# directory (the marker; without it the script is a no-op).
# Run from the repo root, by .github/workflows/template-cleanup.yml or by hand.
# Bash 3.2 compatible, so it also runs by hand on macOS.
#
# Usage: .github/template-cleanup/cleanup.sh [<project-name>]   (default: repo folder name)
set -euo pipefail

here=".github/template-cleanup"
if [ ! -d "$here" ]; then
    echo "template-cleanup: nothing to do ($here is gone)"
    exit 0
fi
name="${1:-$(basename "$(git rev-parse --show-toplevel)")}"
files="$here/files"

# Template-only docs, tests, policies (security, contributing, changelog, issue forms) and development
# history. Other .claude/ files (e.g. settings.json) are kept.
rm -rf docs tests SECURITY.md CONTRIBUTING.md CHANGELOG.md .github/ISSUE_TEMPLATE
rm -rf .claude/plans .claude/scratchpad .claude/knowledge .claude/memory
mkdir -p .claude/memory
cp "$files/overview.md" .claude/overview.md
cp "$files/MEMORY.md" .claude/memory/MEMORY.md

cp "$files/CLAUDE.md" CLAUDE.md

# README stub: project name plus a random joke
n_jokes=$(grep -c . "$files/jokes.txt")
joke=$(grep . "$files/jokes.txt" | sed -n "$(( RANDOM % n_jokes + 1 ))p")
printf '# %s\n\n> %s\n\nDevelopment environment: see [.devcontainer/README.md](.devcontainer/README.md).\n' \
    "$name" "$joke" > README.md

rm -rf "$here"
echo "template-cleanup: done for '$name'"
