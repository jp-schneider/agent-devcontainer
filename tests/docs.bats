#!/usr/bin/env bats
# Relative links in the template's Markdown resolve: the target file exists, and so does the anchor
# (GitHub heading slugs). Derived repos are checked after cleanup in template-flow.bats.

load helpers

@test "every relative link and anchor in the tracked Markdown resolves" {
    cd "$REPO_ROOT"
    run sh -c "git ls-files -z '*.md' | xargs -0 python3 '$BATS_TEST_DIRNAME/md-links.py' ."
    [ "$output" = "" ] || { echo "$output" >&2; return 1; }
    [ "$status" -eq 0 ]
}

@test "the checker finds a broken file link and a broken anchor" {
    setup_workdir
    mkdir -p "$WORK/d"
    printf '# Title\n\n## Some section\n' > "$WORK/d/page.md"
    printf '[ok](d/page.md#some-section) [no file](d/gone.md) [no anchor](d/page.md#other)\n' > "$WORK/index.md"
    run python3 "$BATS_TEST_DIRNAME/md-links.py" "$WORK" index.md
    teardown_workdir
    [ "$status" -eq 1 ]
    [ "$output" = "index.md: d/gone.md (no such file)
index.md: d/page.md#other (no such anchor)" ]
}
