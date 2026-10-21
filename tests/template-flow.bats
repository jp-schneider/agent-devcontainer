#!/usr/bin/env bats
# Template lifecycle end to end: "Use this template" → cleanup → customize → update 1 (unrelated
# histories, default = latest tag) → update 2 (shared history, explicit tag).
# The scenario runs once in setup_file and records snapshots; each test checks one aspect of them.

load helpers

# snapshot <name>: working tree (without .git), tracked files and unresolved conflicts of $DER
snapshot() {
    mkdir -p "$WORK/$1"
    (cd "$DER" && tar --exclude=./.git -cf - .) | (cd "$WORK/$1" && tar -xf -)
    git -C "$DER" ls-files > "$WORK/$1.ls-files"
    git -C "$DER" diff --name-only --diff-filter=U > "$WORK/$1.conflicts"
    git -C "$DER" diff --cached --name-only | LC_ALL=C sort > "$WORK/$1.staged"
}

setup_file() {
    setup_workdir
    export WORK
    TMPL="$WORK/template"
    DER="$WORK/myproj"

    # Template v0.1.0: the current repo's would-be content
    copy_repo "$TMPL"
    git -c init.defaultBranch=main -C "$TMPL" init -q
    git -C "$TMPL" add -A
    git -C "$TMPL" commit -q -m "template v1"
    git -C "$TMPL" tag v0.1.0

    # "Use this template": same tree, fresh history; then the cleanup workflow's script
    mkdir -p "$DER"
    git -C "$TMPL" archive main | tar -x -C "$DER"
    git -c init.defaultBranch=main -C "$DER" init -q
    git -C "$DER" add -A
    git -C "$DER" commit -q -m "Initial commit"
    (cd "$DER" && "$BASH_UNDER_TEST" .github/template-cleanup/cleanup.sh > "$WORK/cleanup.log")
    git -C "$DER" add -A
    git -C "$DER" commit -q -m "Clean up template files"
    snapshot after-cleanup

    # The project customizes
    echo "- Project rule: be nice" >> "$DER/CLAUDE.md"
    mkdir -p "$DER/.claude/plans" "$DER/docs"
    echo "own plan" > "$DER/.claude/plans/own-plan.md"
    echo "my project" >> "$DER/README.md"
    echo "our own license" > "$DER/LICENSE"
    echo "our own notes" > "$DER/docs/notes.md"
    echo "# our project mounts" >> "$DER/.devcontainer/compose.project.yml"
    git -C "$DER" add -A
    git -C "$DER" commit -q -m "customize"
    echo '{"local": true}' > "$DER/.claude/settings.local.json" # gitignored, must survive

    # Template v0.2.0 (tagged), then unreleased work on main
    echo "# v2 change" >> "$TMPL/.devcontainer/shared/compose.core.yml"
    mkdir -p "$TMPL/.claude/plans" # a published plan; the template tracks none by default
    echo "template plan" > "$TMPL/.claude/plans/2026-10-09-00-00-template-only.md"
    echo "template CLAUDE change" >> "$TMPL/CLAUDE.md"
    echo "v2 docs change" >> "$TMPL/docs/architecture.md"
    echo "new template page" > "$TMPL/docs/new-page.md"
    echo "# template change to project file" >> "$TMPL/.devcontainer/compose.project.yml"
    echo "template security policy change" >> "$TMPL/SECURITY.md"
    echo "template license change" >> "$TMPL/LICENSE"
    echo "# new template test" > "$TMPL/tests/new.bats"
    echo "0.2.0" > "$TMPL/.devcontainer/VERSION"
    git -C "$TMPL" add -A
    git -C "$TMPL" commit -q -m "template v2"
    git -C "$TMPL" tag -a v0.2.0 -m v0.2.0
    git -C "$TMPL" commit -q --allow-empty -m "unreleased work on main"

    # Update 1: no ref → latest tag; unrelated histories
    (cd "$DER" && "$BASH_UNDER_TEST" .devcontainer/update-from-template.sh "" "$TMPL" > "$WORK/update1.log" 2>&1) || true
    snapshot after-update1
    # Resolve the expected conflict with the template's version and commit
    git -C "$DER" checkout -q --theirs .devcontainer/shared/compose.core.yml
    git -C "$DER" add .devcontainer/shared/compose.core.yml
    git -C "$DER" commit -q -m "Merge template v0.2.0"
    snapshot after-merge1

    # Template v0.3.0; update 2 with an explicit tag; shared history now
    echo "# v3 change" >> "$TMPL/.devcontainer/shared/compose.core.yml"
    echo "another template plan" > "$TMPL/.claude/plans/2026-10-10-00-00-template-only-2.md"
    echo "0.3.0" > "$TMPL/.devcontainer/VERSION"
    git -C "$TMPL" add -A
    git -C "$TMPL" commit -q -m "template v3"
    git -C "$TMPL" tag v0.3.0
    (cd "$DER" && "$BASH_UNDER_TEST" .devcontainer/update-from-template.sh v0.3.0 "$TMPL" > "$WORK/update2.log" 2>&1)
    snapshot after-update2
    git -C "$DER" diff --cached .devcontainer/shared/compose.core.yml > "$WORK/update2.core.diff"
}

teardown_file() {
    teardown_workdir
}

# --- Cleanup

@test "cleanup: template-only files removed, marker gone" {
    S="$WORK/after-cleanup"
    for p in docs tests .vscode/tasks.json .devcontainer/template-dev SECURITY.md CONTRIBUTING.md CHANGELOG.md .github/template-cleanup .github/release; do
        [ ! -e "$S/$p" ] || { echo "still there: $p" >&2; return 1; }
    done
}

@test "cleanup: README stub, generic CLAUDE.md, reset .claude/, VERSION kept" {
    S="$WORK/after-cleanup"
    [ "$(head -n 1 "$S/README.md")" = "# myproj" ]
    sed -n 3p "$S/README.md" | grep -q '^> .'
    cmp -s "$S/CLAUDE.md" "$WORK/template/.github/template-cleanup/files/CLAUDE.md"
    # The template ships .claude/settings.json (deny rules); cleanup keeps it on purpose
    [ "$(grep '^\.claude/' "$WORK/after-cleanup.ls-files" | grep -v '^\.claude/settings\.json$' | LC_ALL=C sort | tr '\n' ' ')" \
        = ".claude/memory/MEMORY.md .claude/overview.md " ]
    [ "$(cat "$S/.devcontainer/VERSION")" = "0.1.0" ]
}

@test "cleanup: workflow files stay (a GITHUB_TOKEN push can't delete them), .devcontainer untouched" {
    [ -f "$WORK/after-cleanup/.github/workflows/template-cleanup.yml" ]
    # The template moved on since; compare with its v0.1.0 tree (minus the template-only variant)
    git -C "$WORK/template" archive v0.1.0 .devcontainer | (mkdir -p "$WORK/v010" && cd "$WORK/v010" && tar -xf -)
    [ -d "$WORK/v010/.devcontainer/template-dev" ]
    diff -rq -x template-dev -x LICENSE "$WORK/after-cleanup/.devcontainer" "$WORK/v010/.devcontainer"
}

@test "cleanup: the template's LICENSE moves to .devcontainer/, the root is left to the project" {
    S="$WORK/after-cleanup"
    [ ! -e "$S/LICENSE" ]
    git -C "$WORK/template" show v0.1.0:LICENSE | cmp -s "$S/.devcontainer/LICENSE" -
}

# --- Update 1: unrelated histories, default ref

@test "update 1: no ref picks the latest release tag (not newer main) and reports the version change" {
    grep -qF '0.1.0 -> 0.2.0 (ref v0.2.0)' "$WORK/update1.log"
}

@test "update 1: project-owned files keep the project's version" {
    S="$WORK/after-update1"
    tail -n 1 "$S/CLAUDE.md" | grep -q 'be nice'
    tail -n 1 "$S/README.md" | grep -q 'my project'
    tail -n 1 "$S/.devcontainer/compose.project.yml" | grep -q 'our project mounts'
    [ -f "$S/.claude/plans/own-plan.md" ]
    [ "$(grep '^docs/' "$WORK/after-update1.ls-files")" = "docs/notes.md" ]
    [ "$(ls "$S/docs")" = "notes.md" ]
    [ "$(cat "$S/LICENSE")" = "our own license" ]
}

@test "update 1: .devcontainer/LICENSE is the new template version's LICENSE" {
    git -C "$WORK/template" show v0.2.0:LICENSE | cmp -s "$WORK/after-update1/.devcontainer/LICENSE" -
    tail -n 1 "$WORK/after-update1/.devcontainer/LICENSE" | grep -q 'template license change'
}

@test "update 1: template-only files are not merged back in" {
    S="$WORK/after-update1"
    for p in .claude/plans/2026-10-09-00-00-template-only.md .github/template-cleanup SECURITY.md tests .vscode/tasks.json .github/release .devcontainer/template-dev; do
        [ ! -e "$S/$p" ] || { echo "re-added: $p" >&2; return 1; }
        not_grep "^$p" "$WORK/after-update1.ls-files"
    done
}

@test "update 1: ignored local files survive" {
    [ -f "$WORK/after-update1/.claude/settings.local.json" ]
}

@test "update 1: only the real conflict remains (VERSION resolved to the template's)" {
    [ "$(cat "$WORK/after-update1.conflicts")" = ".devcontainer/shared/compose.core.yml" ]
    [ "$(cat "$WORK/after-update1/.devcontainer/VERSION")" = "0.2.0" ]
}

@test "update 1: after resolving, the template change is in" {
    tail -n 1 "$WORK/after-merge1/.devcontainer/shared/compose.core.yml" | grep -q 'v2 change'
}

# --- Update 2: shared history, explicit tag

@test "update 2: explicit tag, version change reported, no conflicts" {
    grep -qF '0.2.0 -> 0.3.0 (ref v0.3.0)' "$WORK/update2.log"
    [ ! -s "$WORK/after-update2.conflicts" ]
}

@test "update 2: exactly the template change and VERSION are staged" {
    [ "$(tr '\n' ' ' < "$WORK/after-update2.staged")" = ".devcontainer/VERSION .devcontainer/shared/compose.core.yml " ]
    grep -q '^+# v3 change' "$WORK/update2.core.diff"
}

@test "update 2: project-owned files unchanged, template plans still not added" {
    S="$WORK/after-update2"
    tail -n 1 "$S/CLAUDE.md" | grep -q 'be nice'
    [ -f "$S/.claude/plans/own-plan.md" ]
    [ ! -e "$S/.claude/plans/2026-10-10-00-00-template-only-2.md" ]
}
