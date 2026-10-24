#!/usr/bin/env bats
# .github/release/prepare.sh: VERSION bump, CHANGELOG [Unreleased] → [X.Y.Z] - date, release notes
# on stdout; refusals leave both files untouched.

load helpers

PREPARE="$REPO_ROOT/.github/release/prepare.sh"

setup() {
    setup_workdir
    R="$WORK/repo"
    mkdir -p "$R/.devcontainer"
    echo "0.1.0" > "$R/.devcontainer/VERSION"
    cat > "$R/CHANGELOG.md" << 'EOF'
# Changelog

Intro.

## [Unreleased]

### Added
- New thing.

### Changed
- Old thing.

## [0.1.0] - 2026-10-01

### Added
- First.
EOF
    cp "$R/CHANGELOG.md" "$WORK/CHANGELOG.orig"
}

teardown() {
    teardown_workdir
}

# prepare <args...>: run prepare.sh in the scratch repo (run uses a subshell, so cd stays local)
prepare() {
    run _prepare "$@"
}
_prepare() {
    cd "$R" && "$BASH_UNDER_TEST" "$PREPARE" "$@"
}

# untouched: CHANGELOG and VERSION are as set up (chained: errexit is off inside `if`)
untouched() {
    cmp -s "$R/CHANGELOG.md" "$WORK/CHANGELOG.orig" \
        && [ "$(cat "$R/.devcontainer/VERSION")" = "0.1.0" ]
}

@test "release: VERSION set, [Unreleased] dated, fresh empty [Unreleased] above it" {
    prepare 0.2.0 2026-10-21
    [ "$status" -eq 0 ]
    [ "$(cat "$R/.devcontainer/VERSION")" = "0.2.0" ]
    [ "$(grep '^## ' "$R/CHANGELOG.md" | tr '\n' '|')" = "## [Unreleased]|## [0.2.0] - 2026-10-21|## [0.1.0] - 2026-10-01|" ]
    # Nothing between the new [Unreleased] and the new version heading but a blank line
    [ "$(sed -n '/^## \[Unreleased\]/,/^## \[0.2.0\]/p' "$R/CHANGELOG.md" | wc -l | tr -d ' ')" = "3" ]
    # Everything else unchanged
    diff <(grep -v '^## \[\(Unreleased\|0\.2\.0\)\]' "$R/CHANGELOG.md" | cat -s) \
        <(grep -v '^## \[Unreleased\]' "$WORK/CHANGELOG.orig" | cat -s)
}

@test "release: notes are the [Unreleased] body without surrounding blank lines" {
    prepare 0.2.0 2026-10-21
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '### Added\n- New thing.\n\n### Changed\n- Old thing.')" ]
}

@test "release: refuses bad versions and dates, files untouched" {
    for v in v0.2.0 0.2 0.2.0-rc1 01.2.0 "" "0.2.0 "; do
        prepare "$v" 2026-10-21
        [ "$status" -eq 1 ] || { echo "accepted: '$v'" >&2; return 1; }
    done
    prepare 0.2.0 21.10.2026
    [ "$status" -eq 1 ]
    untouched
}

@test "release: refuses an existing version (exact match) and an empty [Unreleased]" {
    prepare 0.1.0 2026-10-21
    [ "$status" -eq 1 ]
    output_has "already has a section for 0.1.0"
    untouched
    # A longer version with the same prefix is a different version: [0.1.10] doesn't block 0.1.1
    sed -i.bak 's/^## \[0\.1\.0\]/## [0.1.10]/' "$R/CHANGELOG.md"
    prepare 0.1.1 2026-10-21
    [ "$status" -eq 0 ]
    printf '# Changelog\n\n## [Unreleased]\n\n## [0.1.0] - 2026-10-01\n' > "$R/CHANGELOG.md"
    prepare 0.3.0 2026-10-21
    [ "$status" -eq 1 ]
    output_has "is empty"
}

@test "release: the repo's own CHANGELOG is in a releasable format" {
    # Format only: right after a release [Unreleased] is empty, so add an entry to the copy first
    awk '{ print } /^## \[Unreleased\]/ { print ""; print "- format check entry" }' \
        "$REPO_ROOT/CHANGELOG.md" > "$R/CHANGELOG.md"
    prepare 99.0.0 2026-10-21
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | head -n 1)" = "- format check entry" ]
    grep -qx '## \[99.0.0\] - 2026-10-21' "$R/CHANGELOG.md"
}

@test "negative control: untouched() detects a change" {
    echo "x" >> "$R/CHANGELOG.md"
    if untouched; then
        echo "untouched() missed a change" >&2
        return 1
    fi
}

# --- prepare.sh --notes

@test "notes: prints a dated section's body, changes nothing" {
    prepare 0.2.0 2026-10-21
    cp "$R/CHANGELOG.md" "$WORK/CHANGELOG.released"
    prepare --notes 0.2.0
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '### Added\n- New thing.\n\n### Changed\n- Old thing.')" ]
    prepare --notes 0.1.0
    [ "$output" = "$(printf '### Added\n- First.')" ]
    cmp -s "$R/CHANGELOG.md" "$WORK/CHANGELOG.released"
}

@test "notes: refuses a missing or undated version, an empty section, a bad version" {
    prepare --notes 0.3.0
    [ "$status" -eq 1 ]
    output_has "no dated section for 0.3.0"
    # 0.1.1 must not match the section [0.1.10]
    sed -i.bak 's/^## \[0\.1\.0\]/## [0.1.10]/' "$R/CHANGELOG.md"
    prepare --notes 0.1.1
    [ "$status" -eq 1 ]
    printf '# Changelog\n\n## [Unreleased]\n\n## [0.4.0] - 2026-10-21\n\n## [0.1.0] - 2026-10-01\n' > "$R/CHANGELOG.md"
    prepare --notes 0.4.0
    [ "$status" -eq 1 ]
    output_has "is empty"
    prepare --notes v0.1.0
    [ "$status" -eq 1 ]
}

# --- version-to-release.sh: on a scratch repo with tags, as release.yml runs it after a push

DECIDE="$REPO_ROOT/.github/release/version-to-release.sh"

# released_repo: $G with v0.1.0 tagged, then a commit bumping to 0.2.0 via prepare.sh (the merged
# release PR); $BEFORE = the commit before it
released_repo() {
    G="$WORK/git"
    new_repo "$G"
    cp "$WORK/CHANGELOG.orig" "$G/CHANGELOG.md"
    echo "0.1.0" > "$G/.devcontainer/VERSION"
    git -C "$G" add -A
    git -C "$G" commit -q -m "v0.1.0"
    git -C "$G" tag -a v0.1.0 -m v0.1.0
    BEFORE="$(git -C "$G" rev-parse HEAD)"
    (cd "$G" && "$BASH_UNDER_TEST" "$PREPARE" 0.2.0 2026-10-21 > /dev/null)
    git -C "$G" commit -q -am "Release v0.2.0"
}

# decide <before>
decide() {
    run _decide "$@"
}
_decide() {
    cd "$G" && "$BASH_UNDER_TEST" "$DECIDE" "$@"
}

@test "decide: a merged version bump releases that version" {
    released_repo
    decide "$BEFORE"
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.0" ]
}

@test "decide: unchanged VERSION releases nothing (exit 0, no version)" {
    released_repo
    echo "docs" > "$G/f"
    git -C "$G" commit -q -am "docs only"
    decide "$(git -C "$G" rev-parse HEAD~1)"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -cx '[0-9.]*')" = "0" ]
    output_has "nothing to release"
}

@test "decide: inconsistent bumps fail (existing tag, not greater, no dated section)" {
    released_repo
    git -C "$G" tag -a v0.2.0 -m v0.2.0
    decide "$BEFORE"
    [ "$status" -eq 1 ]
    output_has "tag v0.2.0 already exists"
    git -C "$G" tag -d v0.2.0 > /dev/null
    git -C "$G" tag -a v0.10.0 -m v0.10.0 # numerically greater than 0.2.0 (not as a string)
    decide "$BEFORE"
    [ "$status" -eq 1 ]
    output_has "not greater than the existing tag v0.10.0"
    git -C "$G" tag -d v0.10.0 > /dev/null
    echo "0.3.0" > "$G/.devcontainer/VERSION" # bumped by hand, without prepare.sh
    git -C "$G" commit -q -am "bump without changelog"
    decide "$BEFORE"
    [ "$status" -eq 1 ]
    output_has "no usable section for 0.3.0"
}

@test "decide: no previous commit (all-zero before) counts as a change" {
    released_repo
    decide 0000000000000000000000000000000000000000
    [ "$status" -eq 0 ]
    [ "$output" = "0.2.0" ]
}
