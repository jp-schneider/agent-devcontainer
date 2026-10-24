#!/usr/bin/env bash
# Prepares a release: sets .devcontainer/VERSION, turns the CHANGELOG's [Unreleased] section into
# [<version>] - <date> with a fresh empty [Unreleased] above it, commits both files as
# "Release v<version>", and prints that section's body (the release notes) to stdout. Needs a clean
# working tree (untracked files count), so the commit holds only the release. The maintainer opens
# a pull request with it; merging it publishes the release (release.yml).
# --notes prints the body of an already dated section (what release.yml publishes) and changes
# nothing.
# Run from the repo root. Bash 3.2 compatible.
#
# Usage: .github/release/prepare.sh <X.Y.Z> [<YYYY-MM-DD>]   (default date: today, UTC)
#        .github/release/prepare.sh --notes <X.Y.Z>
set -euo pipefail

notes_only=""
if [ "${1:-}" = "--notes" ]; then
    notes_only=1
    shift
fi
version="${1:-}"
date="${2:-$(date -u +%Y-%m-%d)}"
changelog=CHANGELOG.md

fail() {
    echo "prepare: $*" >&2
    exit 1
}

# section_body <heading prefix>: body of the CHANGELOG section whose heading starts with the prefix
# (fixed string, so the dots in a version are not regex wildcards), without leading and trailing
# blank lines
section_body() {
    awk -v h="$1" '
        index($0, h) == 1 { inside = 1; next }
        inside && /^## / { exit }
        inside { print }
    ' "$changelog" | sed -e '/./,$!d'
}

printf '%s\n' "$version" | grep -Eqx '(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)' \
    || fail "version must be X.Y.Z without a leading v (got '$version')"
[ -f "$changelog" ] || fail "$changelog not found (run from the repo root)"

if [ -n "$notes_only" ]; then
    grep -qF "## [$version] - " "$changelog" || fail "$changelog has no dated section for $version"
    notes="$(section_body "## [$version] - ")"
    [ -n "$notes" ] || fail "the section for $version in $changelog is empty"
    printf '%s\n' "$notes"
    exit 0
fi

printf '%s\n' "$date" | grep -Eqx '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    || fail "date must be YYYY-MM-DD (got '$date')"
[ -f .devcontainer/VERSION ] || fail ".devcontainer/VERSION not found (run from the repo root)"
grep -q '^## \[Unreleased\]' "$changelog" || fail "$changelog has no '## [Unreleased]' section"
if awk -v h="## [$version]" 'index($0, h) == 1 { found = 1 } END { exit !found }' "$changelog"; then
    fail "$changelog already has a section for $version"
fi

notes="$(section_body "## [Unreleased]")"
[ -n "$notes" ] || fail "the [Unreleased] section in $changelog is empty"
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || fail "not inside a git repository"
[ -z "$(git status --porcelain)" ] || fail "working tree not clean, commit or stash first"

tmp="$changelog.tmp.$$"
awk -v v="$version" -v d="$date" '
    !done && /^## \[Unreleased\]/ { print; print ""; print "## [" v "] - " d; done = 1; next }
    { print }
' "$changelog" > "$tmp"
mv "$tmp" "$changelog"
printf '%s\n' "$version" > .devcontainer/VERSION
git commit -q -m "Release v$version" -- "$changelog" .devcontainer/VERSION \
    || fail "$changelog and .devcontainer/VERSION are updated but the commit failed; commit them yourself"

printf '%s\n' "$notes"
