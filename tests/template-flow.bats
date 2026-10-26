#!/usr/bin/env bats
# Template lifecycle end to end: "Use this template" → cleanup → customize → update 1 (unrelated
# histories, merge base = the release in VERSION, default = latest tag) → update 2 (shared history,
# explicit tag); then squashed history and the unrelated-histories fallback on clones.
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
    TMPL="$WORK/template"
    DER="$WORK/myproj"
    export WORK TMPL DER

    # Template v0.1.0: the current repo's would-be content
    copy_repo "$TMPL"
    # The fixture's own version, so tag and VERSION agree whatever the repo's real version is
    echo "0.1.0" > "$TMPL/.devcontainer/VERSION"
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
    # As the cleanup workflow runs it (CI sets GITHUB_ACTIONS too; the by-hand run is its own test)
    (cd "$DER" && GITHUB_ACTIONS=true "$BASH_UNDER_TEST" .github/template-cleanup/cleanup.sh > "$WORK/cleanup.log")
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
    echo "our-pkg" >> "$DER/.devcontainer/apt-packages.txt"
    echo "# our core tweak" >> "$DER/.devcontainer/shared/compose.core.yml" # conflicts with v2
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
    echo "template-pkg" >> "$TMPL/.devcontainer/apt-packages.txt"
    echo "template security policy change" >> "$TMPL/SECURITY.md"
    echo "template license change" >> "$TMPL/LICENSE"
    echo "# new template test" > "$TMPL/tests/new.bats"
    echo "0.2.0" > "$TMPL/.devcontainer/VERSION"
    git -C "$TMPL" add -A
    git -C "$TMPL" commit -q -m "template v2"
    git -C "$TMPL" tag -a v0.2.0 -m v0.2.0
    git -C "$TMPL" commit -q --allow-empty -m "unreleased work on main"

    # Update 1: no ref → latest tag; unrelated histories, base v0.1.0 (VERSION)
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
    # Changes to files the derived repo doesn't have: git reports modify/delete conflicts for them,
    # which the script resolves (docs/ is project-owned there, CHANGELOG.md and tests/ template-only)
    echo "v3 docs change" >> "$TMPL/docs/architecture.md"
    echo "v3 changelog change" >> "$TMPL/CHANGELOG.md"
    echo "# v3 test change" >> "$TMPL/tests/helpers.bash"
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
    [ -f "$WORK/after-cleanup/.github/workflows/release.yml" ]
    [ -f "$WORK/after-cleanup/.github/workflows/tests.yml" ]
    # The template moved on since; compare with its v0.1.0 tree (minus the template-only variant)
    git -C "$WORK/template" archive v0.1.0 .devcontainer | (mkdir -p "$WORK/v010" && cd "$WORK/v010" && tar -xf -)
    [ -d "$WORK/v010/.devcontainer/template-dev" ]
    diff -rq -x template-dev -x LICENSE "$WORK/after-cleanup/.devcontainer" "$WORK/v010/.devcontainer"
}

@test "cleanup by hand (outside GitHub Actions): also removes the template's workflow files" {
    H="$WORK/by-hand"
    mkdir -p "$H"
    git -C "$WORK/template" archive v0.1.0 | tar -x -C "$H"
    (cd "$H" && env -u GITHUB_ACTIONS "$BASH_UNDER_TEST" .github/template-cleanup/cleanup.sh myproj > /dev/null)
    [ ! -e "$H/.github/workflows/tests.yml" ]
    [ ! -e "$H/.github/workflows/template-cleanup.yml" ]
    [ ! -e "$H/.github/workflows/release.yml" ]
    [ ! -e "$H/.github/template-cleanup" ]
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
    [ "$(tail -n 1 "$S/.devcontainer/apt-packages.txt")" = "our-pkg" ]
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

@test "update 1: no shared history, so the release in VERSION is the merge base" {
    grep -qF 'no shared history with the template' "$WORK/update1.log"
    grep -qF 'merge base: v0.1.0' "$WORK/update1.log"
}

@test "update 1: the commit has the template as second parent (shared history from now on)" {
    # HEAD is "Merge template v0.2.0" (update 2 is staged, not committed)
    [ "$(git -C "$DER" rev-parse HEAD^2)" = "$(git -C "$TMPL" rev-parse 'v0.2.0^{commit}')" ]
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

@test "update 2: template changes to files the project doesn't have stay out, git's report not shown" {
    S="$WORK/after-update2"
    [ ! -e "$S/docs/architecture.md" ]
    [ ! -e "$S/CHANGELOG.md" ]
    [ ! -e "$S/tests/helpers.bash" ]
    [ "$(cat "$S/docs/notes.md")" = "our own notes" ]
    # git's merge report would list these as "deleted in HEAD and modified" conflicts
    not_grep 'CONFLICT\|Automatic merge failed' "$WORK/update2.log"
}

# --- Clean working tree check (on clones of the derived repo after update 1, with a submodule)

# clean_repo <dir>: clone of $DER at "Merge template v0.2.0" with a submodule "lib"
clean_repo() {
    git clone -q "$DER" "$1"
    new_repo "$1-lib"
    git -C "$1" -c protocol.file.allow=always submodule -q add "$1-lib" lib
    git -C "$1" commit -q -m "add lib"
}
# update_in <dir>: update-from-template.sh v0.3.0 there; sets $status/$output
update_in() {
    run bash -c 'cd "$1" && "$2" .devcontainer/update-from-template.sh v0.3.0 "$3"' _ "$1" "$BASH_UNDER_TEST" "$TMPL"
}

@test "clean check: changes inside a submodule and a new unstaged submodule commit don't block, stay as they are" {
    C="$WORK/clean-sub"
    clean_repo "$C"
    echo "work in progress" >> "$C/lib/f"
    echo "new" > "$C/lib/new" && git -C "$C/lib" add new && git -C "$C/lib" commit -q -m "lib work"
    echo "untracked in lib" > "$C/lib/u"
    update_in "$C"
    [ "$status" -eq 0 ]
    [ "$(git -C "$C" diff --cached --name-only | LC_ALL=C sort | tr '\n' ' ')" = ".devcontainer/VERSION .devcontainer/shared/compose.core.yml " ]
    [ "$(git -C "$C" diff --name-only)" = lib ] # the new submodule commit: still unstaged
    grep -q 'work in progress' "$C/lib/f"
    [ -f "$C/lib/u" ]
}

@test "clean check: a staged submodule commit, a tracked change or an untracked file blocks, no merge started" {
    C="$WORK/clean-block"
    clean_repo "$C"
    echo "new" > "$C/lib/new" && git -C "$C/lib" add new && git -C "$C/lib" commit -q -m "lib work"
    git -C "$C" add lib
    update_in "$C"
    [ "$status" -ne 0 ]
    output_has "working tree not clean"
    git -C "$C" reset -q
    git -C "$C" -c protocol.file.allow=always submodule -q update lib
    for change in "echo x >> '$C/README.md'" "echo x > '$C/untracked'"; do
        eval "$change"
        update_in "$C"
        [ "$status" -ne 0 ]
        output_has "working tree not clean"
        ! git -C "$C" rev-parse -q --verify MERGE_HEAD > /dev/null
        git -C "$C" checkout -q -- README.md
        rm -f "$C/untracked"
    done
}

@test "merge did not start: git's own message is shown" {
    C="$WORK/no-start"
    git clone -q "$DER" "$C"
    # git wrapper: `merge` fails before starting (as with untracked files in the way), the rest is git
    mkdir -p "$WORK/fakegit"
    printf '#!/usr/bin/env bash\n[ "$1" = merge ] && { echo "error: fake merge refusal" >&2; exit 1; }\nexec %s "$@"\n' \
        "$(command -v git)" > "$WORK/fakegit/git"
    chmod +x "$WORK/fakegit/git"
    PATH="$WORK/fakegit:$PATH" update_in "$C"
    [ "$status" -ne 0 ]
    output_has "error: fake merge refusal"
    output_has "merge did not start"
}

# squashed_repo <dir>: clone of $DER whose "Merge template v0.2.0" is squashed (template parent dropped)
squashed_repo() {
    git clone -q "$DER" "$1"
    git -C "$1" reset -q --hard "$(git -C "$1" commit-tree 'HEAD^{tree}' -p HEAD^1 -m "Update (squashed)")"
    ! git -C "$1" merge-base HEAD "$(git -C "$TMPL" rev-parse 'v0.3.0^{commit}')" > /dev/null 2>&1
}

@test "squashed update: base from VERSION, only template changes staged, no conflicts; commit re-links" {
    C="$WORK/squashed"
    squashed_repo "$C"
    # changed on both sides without overlap: needs the file-level merge, not just the tree merge
    { echo "# our first line"; cat "$C/.devcontainer/shared/compose.core.yml"; } > "$C/core.tmp"
    mv "$C/core.tmp" "$C/.devcontainer/shared/compose.core.yml"
    git -C "$C" commit -q -am "our core change"
    update_in "$C"
    [ "$status" -eq 0 ]
    output_has "merge base: v0.2.0"
    [ -z "$(git -C "$C" diff --name-only --diff-filter=U)" ]
    [ "$(git -C "$C" diff --cached --name-only | LC_ALL=C sort | tr '\n' ' ')" = ".devcontainer/VERSION .devcontainer/shared/compose.core.yml " ]
    tail -n 1 "$C/.devcontainer/shared/compose.core.yml" | grep -q 'v3 change'
    head -n 1 "$C/.devcontainer/shared/compose.core.yml" | grep -q 'our first line'
    [ ! -e "$C/CHANGELOG.md" ]
    git -C "$C" commit -q --no-edit
    [ "$(git -C "$C" log -1 --format=%s)" = "Update devcontainer template to 0.3.0 (v0.3.0)" ]
    [ "$(git -C "$C" rev-parse HEAD^2)" = "$(git -C "$TMPL" rev-parse 'v0.3.0^{commit}')" ]
}

@test "squashed update: a VERSION without a release tag falls back to unrelated histories" {
    C="$WORK/squashed-untagged"
    squashed_repo "$C"
    echo "0.2.5" > "$C/.devcontainer/VERSION"
    git -C "$C" commit -q -am "VERSION without a tag"
    update_in "$C"
    [ "$status" -eq 0 ]
    not_grep 'merge base:' <<< "$output"
    # add/add conflicts on every file that differs, as on a first update without a base
    git -C "$C" diff --name-only --diff-filter=U | grep -qx .devcontainer/shared/compose.core.yml
}

@test "squashed update: a refused merge (read-tree) stops with git's message, nothing staged" {
    C="$WORK/squashed-blocked"
    squashed_repo "$C"
    # git wrapper: read-tree refuses (as with untracked files in the way), the rest is git
    mkdir -p "$WORK/fakegit-rt"
    printf '#!/usr/bin/env bash\n[ "$1" = read-tree ] && { echo "error: fake read-tree refusal" >&2; exit 128; }\nexec %s "$@"\n' \
        "$(command -v git)" > "$WORK/fakegit-rt/git"
    chmod +x "$WORK/fakegit-rt/git"
    PATH="$WORK/fakegit-rt:$PATH" update_in "$C"
    [ "$status" -ne 0 ]
    output_has "error: fake read-tree refusal"
    output_has "merge did not start"
    [ -z "$(git -C "$C" diff --cached --name-only)" ]
    ! git -C "$C" rev-parse -q --verify MERGE_HEAD > /dev/null
}

# in_way_repo <dir>: clone of $DER with ignored local files where the template has files this repo
# doesn't track (template-only CHANGELOG.md and tests/…): CHANGELOG.md, and a file "tests"
in_way_repo() {
    git clone -q "$DER" "$1"
    echo "my local changelog" > "$1/CHANGELOG.md"
    echo "a file where the template has a directory" > "$1/tests"
    printf 'CHANGELOG.md\nCHANGELOG.md.bak*\ntests\ntests.bak*\n' >> "$1/.git/info/exclude" # clean check passes
}
# update_answers <dir> <answers (printf %b)> [options...]: update to v0.3.0, answers on stdin
update_answers() {
    local dir="$1" answers="$2"
    shift 2
    run env ANSWERS="$answers" bash -c 'd="$1"; shift; cd "$d" && printf "%b" "$ANSWERS" | "$@"' _ \
        "$dir" "$BASH_UNDER_TEST" .devcontainer/update-from-template.sh "$@" v0.3.0 "$TMPL"
}
# untouched_in_way <dir>: the ignored files are as created, no backups, no merge started
untouched_in_way() {
    [ "$(cat "$1/CHANGELOG.md")" = "my local changelog" ] && [ -f "$1/tests" ] \
        && [ ! -e "$1/CHANGELOG.md.bak" ] && [ ! -e "$1/tests.bak" ] \
        && ! git -C "$1" rev-parse -q --verify MERGE_HEAD > /dev/null \
        && [ -z "$(git -C "$1" diff --cached --name-only)" ]
}

@test "guard: without a terminal, ignored local files in the way stop the update, nothing touched" {
    C="$WORK/ignored-in-way"
    in_way_repo "$C"
    update_in "$C"
    [ "$status" -ne 0 ]
    output_has "ignored local files are in the way"
    output_has "  CHANGELOG.md"
    output_has "  tests"
    output_has "--ignored=backup|overwrite"
    untouched_in_way "$C"
}

@test "guard ask: [b]ack up all moves them to <name>.bak, then merges" {
    C="$WORK/ask-backup"
    in_way_repo "$C"
    update_answers "$C" 'b\n' --ignored=ask
    [ "$status" -eq 0 ]
    output_has "moved CHANGELOG.md -> CHANGELOG.md.bak"
    [ "$(cat "$C/CHANGELOG.md.bak")" = "my local changelog" ]
    [ -f "$C/tests.bak" ]
    git -C "$C" rev-parse -q --verify MERGE_HEAD > /dev/null
}

@test "guard ask: [o]verwrite all removes them, then merges" {
    C="$WORK/ask-overwrite"
    in_way_repo "$C"
    update_answers "$C" 'o\n' --ignored=ask
    [ "$status" -eq 0 ]
    output_has "removed CHANGELOG.md"
    [ ! -e "$C/CHANGELOG.md" ] && [ ! -e "$C/CHANGELOG.md.bak" ] && [ ! -e "$C/tests.bak" ]
    git -C "$C" rev-parse -q --verify MERGE_HEAD > /dev/null
}

@test "guard ask: [e]ach file: per-file decisions (sorted order), invalid answers asked again" {
    C="$WORK/ask-each"
    in_way_repo "$C"
    update_answers "$C" 'e\nx\nb\no\n' --ignored=ask
    [ "$status" -eq 0 ]
    output_has "please answer one of"
    [ "$(cat "$C/CHANGELOG.md.bak")" = "my local changelog" ]
    [ ! -e "$C/tests.bak" ] && [ ! -f "$C/tests" ]
}

@test "guard ask: abort at the start, halfway through [e]ach, or at end of input changes nothing" {
    for answers in 'a\n' 'e\nb\na\n' '' 'e\nb\n'; do
        C="$WORK/ask-abort-$RANDOM"
        in_way_repo "$C"
        update_answers "$C" "$answers" --ignored=ask
        [ "$status" -ne 0 ] || { echo "answers '$answers' did not stop" >&2; return 1; }
        output_has "stopped, nothing changed"
        untouched_in_way "$C"
    done
}

@test "guard: --ignored=backup without a terminal; an existing .bak gets the next free name" {
    C="$WORK/flag-backup"
    in_way_repo "$C"
    echo "older backup" > "$C/CHANGELOG.md.bak"
    update_answers "$C" '' --ignored=backup
    [ "$status" -eq 0 ]
    [ "$(cat "$C/CHANGELOG.md.bak")" = "older backup" ]
    [ "$(cat "$C/CHANGELOG.md.bak.1")" = "my local changelog" ]
}

@test "guard: --ignored=overwrite without a terminal; unknown options and modes are refused" {
    C="$WORK/flag-overwrite"
    in_way_repo "$C"
    update_answers "$C" '' --ignored=overwrite
    [ "$status" -eq 0 ]
    [ ! -e "$C/CHANGELOG.md.bak" ]
    for bad in --ignored=keep --frobnicate; do
        update_answers "$WORK/flag-overwrite" '' "$bad"
        [ "$status" -ne 0 ]
        output_has "unknown option '$bad'"
    done
}

@test "guard: ignored files elsewhere don't stop the update" {
    C="$WORK/ignored-elsewhere"
    git clone -q "$DER" "$C"
    echo "local" > "$C/my-notes.txt"
    echo "my-notes.txt" >> "$C/.git/info/exclude"
    update_in "$C"
    [ "$status" -eq 0 ]
    [ "$(cat "$C/my-notes.txt")" = local ]
}
