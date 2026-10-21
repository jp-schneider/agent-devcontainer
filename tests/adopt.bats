#!/usr/bin/env bats
# update-from-template.sh --adopt: an existing repo (not created from the template) with its own
# .gitignore, .vscode/settings.json, .claude/ and devcontainer config → adopt → resolve → regular
# update (shared history now). Plus the refusals.
# The scenario runs once in setup_file and records snapshots; each test checks one aspect of them.

load helpers

# snapshot <name>: working tree (without .git), tracked files, unresolved conflicts, staged paths of $FOR
snapshot() {
    mkdir -p "$WORK/$1"
    (cd "$FOR" && tar --exclude=./.git -cf - .) | (cd "$WORK/$1" && tar -xf -)
    git -C "$FOR" ls-files > "$WORK/$1.ls-files"
    git -C "$FOR" diff --name-only --diff-filter=U > "$WORK/$1.conflicts"
    git -C "$FOR" diff --cached --name-only | LC_ALL=C sort > "$WORK/$1.staged"
}

setup_file() {
    setup_workdir
    export WORK
    TMPL="$WORK/template"
    FOR="$WORK/foreign"
    export TMPL FOR

    # Template v0.1.0: the current repo's would-be content
    copy_repo "$TMPL"
    git -c init.defaultBranch=main -C "$TMPL" init -q
    git -C "$TMPL" add -A
    git -C "$TMPL" commit -q -m "template v1"
    git -C "$TMPL" tag v0.1.0

    # An existing project with its own history and config
    mkdir -p "$FOR/.devcontainer" "$FOR/.vscode" "$FOR/.claude" "$FOR/src"
    git -c init.defaultBranch=main -C "$FOR" init -q
    echo "# Foreign" > "$FOR/README.md"
    printf '__pycache__/\n.venv/\n' > "$FOR/.gitignore"
    echo '{"editor.tabSize": 4}' > "$FOR/.vscode/settings.json"
    echo "our notes" > "$FOR/.claude/notes.md"
    echo '{"image": "python:3.12"}' > "$FOR/.devcontainer/devcontainer.json"
    printf '#!/bin/sh\necho old\n' > "$FOR/.devcontainer/setup.sh"
    chmod +x "$FOR/.devcontainer/setup.sh"
    echo '{"image": "ubuntu"}' > "$FOR/.devcontainer.json"
    echo "SECRET=committed-by-mistake" > "$FOR/prod.env"
    echo "print(1)" > "$FOR/src/main.py"
    git -C "$FOR" add -A
    git -C "$FOR" commit -q -m "existing project"
    git -C "$FOR" rev-parse HEAD > "$WORK/foreign-head"
    snapshot before

    # Adopt: no ref → latest tag; unrelated histories
    (cd "$FOR" && "$BASH_UNDER_TEST" "$TMPL/.devcontainer/update-from-template.sh" --adopt "" "$TMPL" > "$WORK/adopt.log" 2>&1) || true
    snapshot after-adopt
    # Resolve the expected conflict (keep ours plus the template's setting) and commit
    printf '{\n  "editor.tabSize": 4,\n  "git.autoRepositoryDetection": false\n}\n' > "$FOR/.vscode/settings.json"
    git -C "$FOR" add .vscode/settings.json
    git -C "$FOR" commit -q -m "Adopt devcontainer template"

    # Template v0.2.0; regular update with an explicit tag
    echo "# v2 change" >> "$TMPL/.devcontainer/shared/compose.core.yml"
    echo "v2-ignored/" >> "$TMPL/.gitignore"
    echo "# template-only workflow change" >> "$TMPL/.github/workflows/template-cleanup.yml"
    mkdir -p "$TMPL/.claude/plans" # a published plan; the template tracks none by default
    echo "template plan" > "$TMPL/.claude/plans/2026-10-11-00-00-template-only.md"
    echo "template CLAUDE change" >> "$TMPL/CLAUDE.md"
    echo "0.2.0" > "$TMPL/.devcontainer/VERSION"
    git -C "$TMPL" add -A
    git -C "$TMPL" commit -q -m "template v2"
    git -C "$TMPL" tag v0.2.0
    (cd "$FOR" && "$BASH_UNDER_TEST" .devcontainer/update-from-template.sh v0.2.0 "$TMPL" > "$WORK/update.log" 2>&1)
    snapshot after-update
}

teardown_file() {
    teardown_workdir
}

# --- Adopt

@test "adopt: merges the latest tag with the template as a second parent" {
    grep -qF 'unknown -> 0.1.0 (ref v0.1.0)' "$WORK/adopt.log"
    [ "$(git -C "$FOR" rev-parse HEAD^1)" = "$(cat "$WORK/foreign-head")" ]
    [ "$(git -C "$FOR" rev-parse HEAD^2)" = "$(git -C "$TMPL" rev-parse v0.1.0)" ]
}

@test "adopt: previous devcontainer config moved to .devcontainer.legacy/ (content and mode kept)" {
    S="$WORK/after-adopt"
    cmp -s "$S/.devcontainer.legacy/devcontainer.json" "$WORK/before/.devcontainer/devcontainer.json"
    cmp -s "$S/.devcontainer.legacy/setup.sh" "$WORK/before/.devcontainer/setup.sh"
    cmp -s "$S/.devcontainer.legacy/.devcontainer.json" "$WORK/before/.devcontainer.json"
    [ -x "$S/.devcontainer.legacy/setup.sh" ]
    for p in .devcontainer/devcontainer.json .devcontainer/setup.sh .devcontainer.json; do
        [ ! -e "$S/$p" ] || { echo "still there: $p" >&2; return 1; }
        not_grep -x "$p" "$WORK/after-adopt.ls-files"
    done
    output="$(cat "$WORK/adopt.log")"
    output_has ".devcontainer/setup.sh -> .devcontainer.legacy/setup.sh"
}

@test "adopt: .devcontainer/ is the template's (variants, shared core, VERSION)" {
    S="$WORK/after-adopt"
    # The template moved on since (setup_file); compare with v0.1.0
    for p in base/devcontainer.json python-uv-cpu/devcontainer.json shared/compose.core.yml update-from-template.sh; do
        git -C "$TMPL" show "v0.1.0:.devcontainer/$p" | cmp -s "$S/.devcontainer/$p" - \
            || { echo "differs: $p" >&2; return 1; }
    done
    [ "$(cat "$S/.devcontainer/VERSION")" = "0.1.0" ]
}

@test "adopt: missing files seeded from the template (compose.project.yml, deny rules, CLAUDE.md, .claude/ skeleton)" {
    S="$WORK/after-adopt"
    F="$TMPL/.github/template-cleanup/files"
    cmp -s "$S/.devcontainer/compose.project.yml" "$TMPL/.devcontainer/compose.project.yml"
    cmp -s "$S/.claude/settings.json" "$TMPL/.claude/settings.json"
    cmp -s "$S/CLAUDE.md" "$F/CLAUDE.md"
    cmp -s "$S/.claude/overview.md" "$F/overview.md"
    cmp -s "$S/.claude/memory/MEMORY.md" "$F/MEMORY.md"
    git -C "$TMPL" show v0.1.0:LICENSE | cmp -s "$S/.devcontainer/LICENSE" -
    for p in .devcontainer/compose.project.yml .claude/settings.json CLAUDE.md .devcontainer/LICENSE; do
        grep -qx "$p" "$WORK/after-adopt.staged" || { echo "not staged: $p" >&2; return 1; }
    done
}

@test "adopt: the project's own files are kept, template-only files not added" {
    S="$WORK/after-adopt"
    cmp -s "$S/README.md" "$WORK/before/README.md"
    cmp -s "$S/.claude/notes.md" "$WORK/before/.claude/notes.md"
    for p in LICENSE docs tests .vscode/tasks.json .devcontainer/template-dev SECURITY.md CHANGELOG.md .github/template-cleanup .github/release .github/workflows .claude/plans; do
        [ ! -e "$S/$p" ] || { echo "added: $p" >&2; return 1; }
    done
}

@test "adopt: .gitignore = ours + the template's missing lines" {
    S="$WORK/after-adopt"
    [ "$(sed -n 1,2p "$S/.gitignore" | tr '\n' ' ')" = "__pycache__/ .venv/ " ]
    grep -qxF '**/*.env' "$S/.gitignore"
    grep -qxF '.claude-docker/*' "$S/.gitignore"
    not_grep '^[<>=]\{7\}' "$S/.gitignore"
    # every template line is there exactly once
    git -C "$TMPL" show v0.1.0:.gitignore | grep -v '^$' | while IFS= read -r line; do
        [ "$(grep -cxF -- "$line" "$S/.gitignore")" = 1 ] || { echo "count != 1: $line" >&2; return 1; }
    done
}

@test "adopt: only .vscode/settings.json is left as a conflict, with a hint" {
    [ "$(cat "$WORK/after-adopt.conflicts")" = ".vscode/settings.json" ]
    grep -qF 'git.autoRepositoryDetection' "$WORK/adopt.log"
}

@test "adopt: warns about tracked files the new .gitignore ignores" {
    grep -qx '  prod.env' "$WORK/adopt.log"
}

# --- Regular update after adopting (shared history)

@test "update: no conflicts, exactly the template's changes staged" {
    grep -qF '0.1.0 -> 0.2.0 (ref v0.2.0)' "$WORK/update.log"
    [ ! -s "$WORK/after-update.conflicts" ]
    [ "$(tr '\n' ' ' < "$WORK/after-update.staged")" = ".devcontainer/VERSION .devcontainer/shared/compose.core.yml .gitignore " ]
    tail -n 1 "$WORK/after-update/.gitignore" | grep -qx 'v2-ignored/'
}

@test "update: seeded and legacy files stay, template-only files still not added" {
    S="$WORK/after-update"
    [ -f "$S/.devcontainer.legacy/devcontainer.json" ]
    cmp -s "$S/CLAUDE.md" "$TMPL/.github/template-cleanup/files/CLAUDE.md"
    for p in .claude/plans .github/workflows/template-cleanup.yml; do
        [ ! -e "$S/$p" ] || { echo "added: $p" >&2; return 1; }
    done
}

# --- Refusals

@test "refuses --adopt in a repo that already has the template" {
    git -C "$FOR" commit -q -m "update v0.2.0"
    run "$BASH_UNDER_TEST" -c "cd '$FOR' && '$TMPL/.devcontainer/update-from-template.sh' --adopt v0.2.0 '$TMPL'"
    [ "$status" -ne 0 ]
    output_has "already has the template"
    [ -z "$(git -C "$FOR" status --porcelain)" ]
}

@test "refuses --adopt with an existing .devcontainer.legacy/" {
    R="$WORK/legacy-exists"
    new_repo "$R"
    mkdir -p "$R/.devcontainer.legacy"
    echo x > "$R/.devcontainer.legacy/x"
    git -C "$R" add -A
    git -C "$R" commit -q -m legacy
    run "$BASH_UNDER_TEST" -c "cd '$R' && '$TMPL/.devcontainer/update-from-template.sh' --adopt v0.2.0 '$TMPL'"
    [ "$status" -ne 0 ]
    output_has ".devcontainer.legacy already exists"
}

@test "refuses --adopt without a commit" {
    R="$WORK/empty"
    mkdir -p "$R"
    git -c init.defaultBranch=main -C "$R" init -q
    run "$BASH_UNDER_TEST" -c "cd '$R' && '$TMPL/.devcontainer/update-from-template.sh' --adopt v0.2.0 '$TMPL'"
    [ "$status" -ne 0 ]
    output_has "needs at least one commit"
}
