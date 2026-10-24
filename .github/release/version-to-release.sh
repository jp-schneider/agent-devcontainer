#!/usr/bin/env bash
# Decides whether a push to main releases: prints the version to release on stdout, or nothing.
# A release is due when .devcontainer/VERSION differs from <before> (the commit before the push).
# It is then checked for consistency, and an inconsistent bump fails (non-zero) instead of
# releasing: the tag vX.Y.Z must not exist yet, the version must be greater than every vX.Y.Z tag,
# and CHANGELOG.md must have a non-empty dated section for it (prepare.sh --notes).
# Read-only (no tags, no network): release.yml tags and publishes.
# Run from the repo root of a full clone (tags fetched). Bash 3.2 compatible.
#
# Usage: .github/release/version-to-release.sh <before>   (a commit; empty or all zeros: none)
set -euo pipefail

before="${1:-}"
here="$(cd "$(dirname "$0")" && pwd)"

fail() {
    echo "version-to-release: $*" >&2
    exit 1
}

is_version() {
    printf '%s\n' "$1" | grep -Eqx '(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
}

# version_gt <a> <b>: a > b, both X.Y.Z
version_gt() {
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<< "$1"
    IFS=. read -r b1 b2 b3 <<< "$2"
    [ "$a1" -ne "$b1" ] && { [ "$a1" -gt "$b1" ]; return; }
    [ "$a2" -ne "$b2" ] && { [ "$a2" -gt "$b2" ]; return; }
    [ "$a3" -gt "$b3" ]
}

[ -f .devcontainer/VERSION ] || fail ".devcontainer/VERSION not found (run from the repo root)"
version="$(tr -d '[:space:]' < .devcontainer/VERSION)"
is_version "$version" || fail ".devcontainer/VERSION is not X.Y.Z (got '$version')"

previous=""
case "$before" in
    "" | *[!0]*) ;;
    *) before="" ;; # all zeros: no previous commit (a new branch)
esac
if [ -n "$before" ]; then
    previous="$(git show "$before:.devcontainer/VERSION" 2> /dev/null | tr -d '[:space:]')" || previous=""
fi
if [ "$version" = "$previous" ]; then
    echo "version-to-release: VERSION unchanged ($version), nothing to release" >&2
    exit 0
fi

if git rev-parse -q --verify "refs/tags/v$version" > /dev/null; then
    fail "VERSION is $version, but the tag v$version already exists"
fi
for tag in $(git tag -l 'v*'); do
    t="${tag#v}"
    is_version "$t" || continue
    version_gt "$version" "$t" || fail "VERSION $version is not greater than the existing tag $tag"
done
bash "$here/prepare.sh" --notes "$version" > /dev/null \
    || fail "CHANGELOG.md has no usable section for $version (run prepare.sh $version in the PR)"

printf '%s\n' "$version"
