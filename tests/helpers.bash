# Shared helpers for the bats suites (load with `load helpers`).
# shellcheck shell=bash

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
SHARED="$REPO_ROOT/.devcontainer/shared"
# The bash that runs the scripts under test; the macOS CI job sets /bin/bash (3.2)
BASH_UNDER_TEST="${BASH_UNDER_TEST:-bash}"

# Deterministic git, independent of the user's config (signing, default branch, hooks)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# Fresh work dir **outside the workspace**: tests create git repos, which protect-paths.sh would
# treat as planted repos (aborting the next container start) if they lived inside it.
setup_workdir() {
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/devcontainer-tests.XXXXXX")"
    WORK="$(cd "$WORK" && pwd -P)"
    case "$WORK" in
        "$REPO_ROOT"/*)
            echo "work dir $WORK is inside the workspace" >&2
            return 1
            ;;
    esac
}

teardown_workdir() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

# new_repo <dir>: git repo with one commit and a .devcontainer/ dir
new_repo() {
    mkdir -p "$1/.devcontainer"
    git -C "$1" init -q
    git -C "$1" checkout -q -b main 2> /dev/null || true
    touch "$1/f"
    git -C "$1" add -A
    git -C "$1" commit -q -m init
}

# copy_repo <dest>: the repo's tracked + untracked-but-not-ignored files (the would-be template)
copy_repo() {
    mkdir -p "$1"
    (cd "$REPO_ROOT" && git ls-files -co --exclude-standard -z \
        | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
        | tar --null -T - -cf -) | (cd "$1" && tar -xf -)
}

# fake_docker: puts a `docker` on PATH that logs its args to $WORK/docker.log and prints
# "resolved: ok" for `compose -f …`; FAKE_DOCKER_FAIL=1 makes it fail
fake_docker() {
    mkdir -p "$WORK/bin"
    cat > "$WORK/bin/docker" << EOF
#!/usr/bin/env bash
echo "docker \$*" >> "$WORK/docker.log"
[ -n "\${FAKE_DOCKER_FAIL:-}" ] && { echo "fake failure" >&2; exit 1; }
[ "\$1 \$2" = "compose -f" ] && echo "resolved: ok"
exit 0
EOF
    chmod +x "$WORK/bin/docker"
    export PATH="$WORK/bin:$PATH"
}

# yaml_mounts <compose.protect.yml>: one line per bind, "<ro|rw> <source> -> <target>"
yaml_mounts() {
    local py='import sys, yaml
for v in yaml.safe_load(open(sys.argv[1]))["services"]["claude-code"]["volumes"]:
    assert v["type"] == "bind", v
    print(("ro" if v["read_only"] else "rw") + " " + v["source"] + " -> " + v["target"])'
    if python3 -c 'import yaml' 2> /dev/null; then
        python3 -c "$py" "$1"
    else
        uv run -q --with pyyaml python -c "$py" "$1"
    fi
}

# has_mount / lacks_mount <line>: assertions on $MOUNTS (set by the test), with context on failure
has_mount() {
    grep -qxF -- "$1" <<< "$MOUNTS" && return 0
    printf 'missing mount: %s\nmounts:\n%s\n' "$1" "$MOUNTS" >&2
    return 1
}
lacks_mount() {
    grep -qxF -- "$1" <<< "$MOUNTS" || return 0
    printf 'unexpected mount: %s\n' "$1" >&2
    return 1
}

# Plain `! cmd` and `[[ … ]]` don't fail a bats test mid-way (errexit ignores negation, and
# bash 3.2 ignores [[ ]]), so assertions go through functions that return non-zero.

# not_grep <grep args…>: fails if grep matches (stdin or files)
not_grep() {
    if grep -q "$@"; then
        printf 'unexpected match: %s\n' "$*" >&2
        return 1
    fi
}

# output_has <substring>: $output (from `run`) contains it
output_has() {
    case "$output" in
        *"$1"*) return 0 ;;
    esac
    printf 'output lacks: %s\n--- output:\n%s\n' "$1" "$output" >&2
    return 1
}
