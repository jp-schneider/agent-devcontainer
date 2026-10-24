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

# Template-only docs, tests (and their VS Code tasks), the template-dev variant, policies (security,
# contributing, changelog, issue forms), the release script and development history. Other .claude/ files (e.g.
# settings.json) are kept.
rm -rf docs tests .vscode/tasks.json .devcontainer/template-dev SECURITY.md CONTRIBUTING.md CHANGELOG.md .github/ISSUE_TEMPLATE .github/release
rm -rf .claude/plans .claude/scratchpad .claude/knowledge .claude/memory
mkdir -p .claude/memory
cp "$files/overview.md" .claude/overview.md
cp "$files/MEMORY.md" .claude/memory/MEMORY.md

cp "$files/CLAUDE.md" CLAUDE.md

# The template's license covers the files it ships; the root LICENSE is left to the project
[ ! -f LICENSE ] || mv LICENSE .devcontainer/LICENSE

# The template's own workflows (guarded, they never run here). A GITHUB_TOKEN push may not change
# .github/workflows/, so in GitHub Actions they stay and the workflow asks the user to delete them;
# run by hand, the user's own push may, so delete them now.
if [ "${GITHUB_ACTIONS:-}" != true ]; then
    rm -f .github/workflows/tests.yml .github/workflows/release.yml .github/workflows/template-cleanup.yml
fi

# README stub: project name plus a random joke
n_jokes=$(grep -c . "$files/jokes.txt")
joke=$(grep . "$files/jokes.txt" | sed -n "$(( RANDOM % n_jokes + 1 ))p")
printf '# %s\n\n> %s\n\nDevelopment environment: see [.devcontainer/README.md](.devcontainer/README.md).\n' \
    "$name" "$joke" > README.md

rm -rf "$here"
echo "template-cleanup: done for '$name'"
