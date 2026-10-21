#!/usr/bin/env bats
# The template's .gitignore, checked with git check-ignore in a scratch repo: venv dirs and the uv
# toolchain's .venv-<worktree>.ct symlinks (post-start.sh) are ignored at any depth; .claude/private/
# is ignored, the public .claude/ tier is not.

load helpers

setup() {
    setup_workdir
    R="$WORK/repo"
    new_repo "$R"
    cp "$REPO_ROOT/.gitignore" "$R/.gitignore"
    mkdir -p "$R/sub/pkg" "$WORK/venvs"
}

teardown() {
    teardown_workdir
}

# ignored <path>: git ignores <path> in the scratch repo
ignored() {
    git -C "$R" check-ignore -q --no-index -- "$1"
}

@test "uv venv links (symlinks) are ignored, at the root and nested, any worktree name" {
    for p in ".venv-myproj.ct" "sub/pkg/.venv-myproj.ct" ".venv-my proj.v2.ct"; do
        ln -s "$WORK/venvs" "$R/$p"
        ignored "$p" || { echo "not ignored: $p" >&2; return 1; }
    done
}

@test "plain .venv is ignored as a dir and as a symlink, at the root and nested" {
    mkdir "$R/.venv"
    ln -s "$WORK/venvs" "$R/sub/pkg/.venv"
    ignored .venv
    ignored .venv/bin/python
    ignored sub/pkg/.venv
}

@test "negative control: similar names stay visible" {
    for p in "x.venv-a.ct" ".venv-a.ct.bak" ".venv.ct.txt" "venv" "notes.ct"; do
        touch "$R/$p"
        if ignored "$p"; then
            echo "unexpectedly ignored: $p" >&2
            return 1
        fi
    done
}

@test ".claude/private/ is ignored; the public .claude/ tier is not" {
    mkdir -p "$R/.claude/private/plans" "$R/.claude/private/memory" "$R/.claude/plans" "$R/.claude/memory"
    for p in .claude/private/overview.md .claude/private/plans/p.md .claude/private/memory/MEMORY.md; do
        touch "$R/$p"
        ignored "$p" || { echo "not ignored: $p" >&2; return 1; }
    done
    for p in .claude/overview.md .claude/plans/p.md .claude/memory/MEMORY.md .claude/settings.json; do
        touch "$R/$p"
        if ignored "$p"; then
            echo "unexpectedly ignored: $p" >&2
            return 1
        fi
    done
}
