#!/usr/bin/env bash
# Merges updates from the devcontainer template into a repo created from it, or (--adopt) into an
# existing repo that was not. Keeps this repo's own files (see own_paths) and drops template-only
# ones (docs, policies, cleanup). Leaves the merge uncommitted for review.
# Run from the repo root on a clean working tree (submodules may be dirty). Bash 3.2 compatible (macOS).
#
# Usage: .devcontainer/update-from-template.sh [--adopt] [<ref>] [<template-url>]
#   <ref>:   a release tag (e.g. v0.2.0) or a branch. Default: the latest vX.Y.Z tag, else main.
#   --adopt: first merge into a repo not created from the template. Moves its existing
#            .devcontainer/ (and .devcontainer.json) to .devcontainer.legacy/ and seeds missing
#            files (compose.project.yml, apt-packages.txt, .claude/settings.json, CLAUDE.md,
#            .claude/ skeleton).
set -euo pipefail

adopt=""
if [ "${1:-}" = "--adopt" ]; then
    adopt=1
    shift
fi
ref="${1:-}"
url="${2:-https://github.com/jp-schneider/agent-devcontainer.git}"
# Paths owned by this repo, not by the template (the template's copies are never merged in)
own_paths="CLAUDE.md README.md .claude docs .github/template-cleanup .devcontainer/compose.project.yml .devcontainer/apt-packages.txt
LICENSE SECURITY.md CONTRIBUTING.md CHANGELOG.md .github/ISSUE_TEMPLATE tests .vscode/tasks.json .github/workflows/tests.yml
.github/workflows/template-cleanup.yml .github/workflows/release.yml .github/release .devcontainer/template-dev"
legacy=".devcontainer.legacy"

# Submodules' own state (changes inside, new commits) doesn't matter: the template has none, and only
# what is staged gets committed. Anything staged does, a submodule commit too.
if [ -n "$(git status --porcelain --ignore-submodules=all)" ] \
    || ! git diff --cached --quiet --ignore-submodules=none; then
    echo "update-from-template: working tree not clean, commit or stash first (changes inside submodules are fine)" >&2
    exit 1
fi
if [ -n "$adopt" ]; then
    if ! git rev-parse -q --verify HEAD > /dev/null; then
        echo "update-from-template: --adopt needs at least one commit" >&2
        exit 1
    fi
    if git cat-file -e HEAD:.devcontainer/VERSION 2> /dev/null; then
        echo "update-from-template: this repo already has the template (.devcontainer/VERSION); run without --adopt" >&2
        exit 1
    fi
    if [ -e "$legacy" ]; then
        echo "update-from-template: $legacy already exists; move it away first" >&2
        exit 1
    fi
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
echo "update-from-template: $old_version -> $new_version (ref $ref). Changes: https://github.com/jp-schneider/agent-devcontainer/releases"

# The first update has no common history ("Use this template" squashes it)
unrelated=""
if ! git merge-base HEAD "$target" > /dev/null; then
    unrelated="--allow-unrelated-histories"
elif [ -n "$adopt" ]; then
    echo "update-from-template: this repo already shares history with the template; run without --adopt" >&2
    exit 1
fi

# Conflicts are expected; own paths are resolved below, the rest is up to the user. git's own report
# is kept back: it lists conflicts this script resolves (e.g. "deleted in HEAD and modified" for every
# template-only file the template changed); the remaining ones are listed at the end.
# A merge that didn't start (e.g. untracked files in the way) leaves no MERGE_HEAD: stop there.
msg="Update devcontainer template to $new_version ($ref)"
[ -z "$adopt" ] || msg="Adopt devcontainer template $new_version ($ref)"
merge_log="$(mktemp)"
if ! git merge --no-commit --no-ff $unrelated -m "$msg" "$target" > "$merge_log" 2>&1; then
    if ! git rev-parse -q --verify MERGE_HEAD > /dev/null; then
        cat "$merge_log" >&2
        rm -f "$merge_log"
        echo "update-from-template: merge did not start, see git's message above" >&2
        exit 1
    fi
fi
rm -f "$merge_log"

# Only tracked files are touched; untracked/ignored ones (e.g. .claude/settings.local.json) stay
for p in $own_paths; do
    if git cat-file -e "HEAD:$p" 2> /dev/null; then
        # Drop what isn't ours under our path: files the template added, and conflicted ones we don't
        # have (the template changed a file we deleted; checkout HEAD can't resolve those). Then
        # restore ours (also resolves the other conflicts).
        git ls-files -- "$p" | LC_ALL=C sort -u | while IFS= read -r f; do
            git cat-file -e "HEAD:$f" 2> /dev/null || git rm -q -f -- "$f"
        done
        git checkout HEAD -- "$p"
    else
        # Template-only path
        git rm -r -q -f --ignore-unmatch -- "$p"
    fi
done

# Template-owned bookkeeping: always the template's version (conflicts on the first, unrelated merge)
# shellcheck disable=SC2043 # a list of one for now; more template-owned files go here
for p in .devcontainer/VERSION; do
    if git cat-file -e "$target:$p" 2> /dev/null; then
        git checkout "$target" -- "$p"
    fi
done
# The template's license covers the files it ships: kept as .devcontainer/LICENSE, so a root
# LICENSE stays the project's own (see own_paths)
if git cat-file -e "$target:LICENSE" 2> /dev/null; then
    git update-index --add --cacheinfo "100644,$(git rev-parse "$target:LICENSE"),.devcontainer/LICENSE"
    git checkout-index -f -- .devcontainer/LICENSE
fi

moved=""
seeded=""
if [ -n "$adopt" ]; then
    # The repo's previous devcontainer config moves aside (blobs and modes as in HEAD), so
    # .devcontainer/ is the template's. A root .devcontainer.json would also show up in VS Code.
    # Paths under .devcontainer.legacy/ are not scanned by VS Code.
    while IFS="$(printf '\t')" read -r meta p; do
        [ -n "$p" ] || continue
        mode="${meta%% *}"
        sha="${meta##* }"
        dest="$legacy/${p#.devcontainer/}"
        git update-index --add --cacheinfo "$mode,$sha,$dest"
        git checkout-index -f -- "$dest"
        if git cat-file -e "$target:$p" 2> /dev/null; then
            git checkout "$target" -- "$p"
        else
            git rm -q -f -- "$p"
        fi
        moved="$moved  $p -> $dest
"
    done << EOF
$(git ls-tree -r HEAD -- .devcontainer .devcontainer.json)
EOF
fi

# .gitignore is a line list: on a conflict keep ours and append the template's missing lines.
# Needed on the first merge, where both sides added it (add/add).
if [ -n "$(git ls-files -u -- .gitignore)" ]; then
    tmp="$(mktemp)"
    git show :2:.gitignore > "$tmp.ours" 2> /dev/null || : > "$tmp.ours"
    git show :3:.gitignore > "$tmp.theirs" 2> /dev/null || : > "$tmp.theirs"
    awk 'NR == FNR { seen[$0] = 1; print; next }
        $0 != "" && !($0 in seen) { seen[$0] = 1; add[++n] = $0 }
        END { if (n) { print ""; print "# devcontainer template"; for (i = 1; i <= n; i++) print add[i] } }' \
        "$tmp.ours" "$tmp.theirs" > "$tmp"
    cat "$tmp" > .gitignore
    rm -f "$tmp" "$tmp.ours" "$tmp.theirs"
    git add -- .gitignore
fi

if [ -n "$adopt" ]; then
    # Seed what the template's "Use this template" + cleanup would have provided: only where
    # missing (tracked or on disk) and not ignored by this repo
    while read -r dest src; do
        [ -n "$dest" ] || continue
        if git ls-files --error-unmatch -- "$dest" > /dev/null 2>&1 || [ -e "$dest" ]; then
            continue
        fi
        git cat-file -e "$target:$src" 2> /dev/null || continue
        git check-ignore -q -- "$dest" && continue
        git update-index --add --cacheinfo "100644,$(git rev-parse "$target:$src"),$dest"
        git checkout-index -f -- "$dest"
        seeded="$seeded  $dest
"
    done << EOF
.devcontainer/compose.project.yml .devcontainer/compose.project.yml
.devcontainer/apt-packages.txt .devcontainer/apt-packages.txt
.claude/settings.json .claude/settings.json
CLAUDE.md .github/template-cleanup/files/CLAUDE.md
.claude/overview.md .github/template-cleanup/files/overview.md
.claude/memory/MEMORY.md .github/template-cleanup/files/MEMORY.md
EOF
fi

if [ -n "$moved" ]; then
    printf 'update-from-template: moved the previous devcontainer config (port what you need, then delete %s/):\n%s' "$legacy" "$moved"
fi
if [ -n "$seeded" ]; then
    printf 'update-from-template: added from the template:\n%s' "$seeded"
fi
if [ -n "$adopt" ]; then
    now_ignored="$(git ls-files -ci --exclude-standard)"
    if [ -n "$now_ignored" ]; then
        echo "update-from-template: tracked but now ignored (check for secrets; untrack with 'git rm --cached'):"
        echo "$now_ignored" | sed 's/^/  /'
    fi
fi

conflicts="$(git diff --name-only --diff-filter=U)"
case "$conflicts" in
    *.vscode/settings.json*)
        echo "update-from-template: in .vscode/settings.json keep \"git.autoRepositoryDetection\": false (see .devcontainer/README.md)"
        ;;
esac
if [ -n "$conflicts" ]; then
    echo "update-from-template: resolve these conflicts, then 'git commit':"
    echo "$conflicts"
else
    echo "update-from-template: merge staged; review with 'git diff --cached', then 'git commit'"
fi
