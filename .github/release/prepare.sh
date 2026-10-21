#!/usr/bin/env bash
# Prepares a release in the working tree: sets .devcontainer/VERSION, turns the CHANGELOG's
# [Unreleased] section into [<version>] - <date> with a fresh empty [Unreleased] above it, and
# prints that section's body (the release notes) to stdout. Touches no git state:
# .github/workflows/release.yml commits, tags and publishes.
# Run from the repo root. Bash 3.2 compatible.
#
# Usage: .github/release/prepare.sh <X.Y.Z> [<YYYY-MM-DD>]   (default date: today, UTC)
set -euo pipefail

version="${1:-}"
date="${2:-$(date -u +%Y-%m-%d)}"
changelog=CHANGELOG.md

fail() {
    echo "prepare: $*" >&2
    exit 1
}

printf '%s\n' "$version" | grep -Eqx '(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)' \
    || fail "version must be X.Y.Z without a leading v (got '$version')"
printf '%s\n' "$date" | grep -Eqx '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    || fail "date must be YYYY-MM-DD (got '$date')"
[ -f "$changelog" ] || fail "$changelog not found (run from the repo root)"
[ -f .devcontainer/VERSION ] || fail ".devcontainer/VERSION not found (run from the repo root)"
grep -q '^## \[Unreleased\]' "$changelog" || fail "$changelog has no '## [Unreleased]' section"
# Fixed-string match: the dots in the version are not regex wildcards
if awk -v h="## [$version]" 'index($0, h) == 1 { found = 1 } END { exit !found }' "$changelog"; then
    fail "$changelog already has a section for $version"
fi

# Release notes: the [Unreleased] body, without leading and trailing blank lines
notes="$(awk '
    /^## \[Unreleased\]/ { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
' "$changelog" | sed -e '/./,$!d')"
[ -n "$notes" ] || fail "the [Unreleased] section in $changelog is empty"

tmp="$changelog.tmp.$$"
awk -v v="$version" -v d="$date" '
    !done && /^## \[Unreleased\]/ { print; print ""; print "## [" v "] - " d; done = 1; next }
    { print }
' "$changelog" > "$tmp"
mv "$tmp" "$changelog"
printf '%s\n' "$version" > .devcontainer/VERSION

printf '%s\n' "$notes"
