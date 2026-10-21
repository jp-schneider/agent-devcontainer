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
