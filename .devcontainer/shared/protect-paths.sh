#!/usr/bin/env bash
# Generates the protection overlay (listed last in each variant's dockerComposeFile):
# read-only binds over every workspace path that the host executes or trusts, so
# the agent can't tamper with it, and /dev/null over host-only env files.
# Exits non-zero, aborting the container start, if a nested git repository was
# planted in the workspace (host git would run its hooks).
#
# Runs on the host from the workspace root, called from initialize.sh. It is
# trusted because .devcontainer/ is read-only inside the container.
# Must stay bash 3.2 compatible (macOS system bash).
#
# Usage: protect-paths.sh <output-file>
set -uo pipefail

out="$1"
ws="$(pwd -P)"
allowlist=".devcontainer/allowed-nested-git.txt"
defaults_patterns="$(cd "$(dirname "$0")" && pwd -P)/mask-patterns.txt"
project_patterns=""
[ -f .devcontainer/mask-patterns.txt ] && project_patterns=".devcontainer/mask-patterns.txt"

# Fail closed: no stale overlay survives an abort (compose then refuses to start)
rm -f "$out"
mkdir -p "$(dirname "$out")"
if [ ! -f "$defaults_patterns" ]; then
    echo "protect-paths: ABORT, $defaults_patterns is missing" >&2
    exit 1
fi

# --- Placeholders: a path must exist to be bind-mounted read-only
mkdir -p .vscode .claude
# settings.json starts from the template default: Read/Edit deny rules for secret files, mirroring
# mask-patterns.txt as globs (matters for Claude Code run on the host; keep both in sync)
[ -e .claude/settings.json ] || cp "$(dirname "$defaults_patterns")/claude-settings.default.json" .claude/settings.json
[ -e .claude/settings.local.json ] || echo '{}' > .claude/settings.local.json
[ -e .mcp.json ] || echo '{"mcpServers": {}}' > .mcp.json

# --- Git layout. Mirrors GIT_COMMON_DIR in initialize.sh: the common gitdir is mounted
# at the same absolute path (and is also /app/.git in the main worktree).
main_git=""
self_git=""
if common="$(git rev-parse --git-common-dir 2> /dev/null)"; then
    main_git="$(cd "$common" && pwd -P)"
    self_git="$(cd "$(git rev-parse --git-dir)" && pwd -P)"
fi
# Gitdir outside the workspace and not a linked worktree's: the workspace is a submodule
# (<super>/.git/modules/<name>) or uses --separate-git-dir. Its .git pointer and core.worktree
# can be relative to the host layout and are replaced (see relink below).
external=0
if [ -n "$main_git" ] && [ "$self_git" = "$main_git" ] && [ "$main_git" != "$ws/.git" ]; then
    external=1
fi

# resolve_pointer <.git file>: the gitdir it points to, physical path; empty if unresolvable
resolve_pointer() {
    local gitdir
    gitdir="$(sed -n 's/^gitdir: //p' "$1" | head -n 1)"
    (cd "$(dirname "$1")" 2> /dev/null && cd "$gitdir" 2> /dev/null && pwd -P) || true
}

# --- Nested repositories. Known ones are protected like the main repo; unknown ones abort.
violations=""
nested_gitdirs="" # host gitdirs of allowlisted nested repos inside the workspace
pointers=""       # workspace-relative .git pointer files (submodules, allowlisted)
while IFS= read -r g; do
    rel="${g#./}"
    resolved=""
    [ -f "$g" ] && resolved="$(resolve_pointer "$g")"
    if [ -f "$allowlist" ] && grep -qxF "$(dirname "$rel")" "$allowlist"; then
        if [ -d "$g" ]; then
            nested_gitdirs="${nested_gitdirs}${ws}/${rel}"$'\n'
        else
            pointers="${pointers}${rel}"$'\n'
            # Its gitdir needs protecting too if the container can reach it (main gitdir: covered below)
            under_main=0
            if [ -n "$main_git" ]; then
                case "$resolved" in "$main_git" | "$main_git"/*) under_main=1 ;; esac
            fi
            if [ "$under_main" = 0 ]; then
                case "$resolved" in "$ws"/*) nested_gitdirs="${nested_gitdirs}${resolved}"$'\n' ;; esac
            fi
        fi
        continue
    fi
    if [ -n "$resolved" ] && [ -n "$main_git" ]; then
        # Submodule pointer: allowed iff its gitdir lives in a protected modules/ dir
        case "$resolved" in
            "$main_git"/modules/* | "$self_git"/modules/*)
                pointers="${pointers}${rel}"$'\n'
                continue
                ;;
        esac
    fi
    violations="${violations}  ${rel}"$'\n'
done < <(find . -path ./.git -prune -o -name .git -print 2> /dev/null)

if [ -n "$violations" ]; then
    {
        echo "protect-paths: ABORT, nested git repositories found in the workspace:"
        printf '%s' "$violations"
        echo "Host git would use their hooks and config. Remove them; convert old-style submodules"
        echo "with 'git submodule absorbgitdirs'; or, if intended, list the directory (relative to"
        echo "the workspace root, one per line) in $allowlist."
    } >&2
    exit 1
fi

# --- Overlay
tmp="$out.tmp"

# YAML single-quoted scalar; '$' doubled so compose doesn't interpolate
quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g; s/\\\$/\$\$/g")"
}
bind() { # <host-source> <container-target> <read_only: true|false>
    printf '      - type: bind\n        source: %s\n        target: %s\n        read_only: %s\n' \
        "$(quote "$1")" "$(quote "$2")" "$3" >> "$tmp"
}
protect_gitdir() { # <host-gitdir> <container-gitdir> [<config-source>]: everything in it that host git executes or follows
    mkdir -p "$1/hooks" "$1/modules" "$1/worktrees"
    bind "$1/hooks" "$2/hooks" true
    bind "${3:-$1/config}" "$2/config" true
    bind "$1/modules" "$2/modules" true
    bind "$1/worktrees" "$2/worktrees" true
}

# Relinked gitdirs (gitdir outside the workspace, mounted at its own path; see external above):
# relink <host-gitdir> <container-worktree> writes $link.git, a pointer with the absolute gitdir,
# and $link.config, which includes the host config and then sets core.worktree. The include reads
# the host config through a read-only bind of main_git at $host_git_view, so host changes stay
# live (git rewrites config by rename; a single-file bind would keep the old inode).
links="$(cd "$(dirname "$out")" && pwd -P)/git-links"
host_git_view=/opt/host-gitdir
rm -rf "$links"
n=0
link=""
gitconfig_quote() { # double-quoted git config value
    printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')"
}
relink() {
    mkdir -p "$links"
    n=$((n + 1))
    link="$links/$n"
    printf 'gitdir: %s\n' "$1" > "$link.git"
    printf '[include]\n\tpath = %s\n[core]\n\tworktree = %s\n' \
        "$(gitconfig_quote "$host_git_view${1#"$main_git"}/config")" "$(gitconfig_quote "$2")" > "$link.config"
}

cat > "$tmp" <<'EOF'
# Auto-generated by .devcontainer/shared/protect-paths.sh, do not edit.
# Read-only binds over host-executed/trusted paths; /dev/null over host-only env files.
services:
  claude-code:
    volumes:
EOF

# Workspace paths the host executes or trusts.
# DEVCONTAINER_EDITABLE_BY_AGENT=1 in .env (host-only, masked in the container) leaves
# .devcontainer/ writable, e.g. for developing this template from inside the container.
# That removes the trust anchor: the agent can then change what runs on the host at the
# next start.
if grep -qx 'DEVCONTAINER_EDITABLE_BY_AGENT=1' .env 2> /dev/null; then
    echo "protect-paths: WARNING .devcontainer/ is writable by the agent (DEVCONTAINER_EDITABLE_BY_AGENT=1 in .env)." >&2
    echo "protect-paths: WARNING review 'git diff -- .devcontainer' before every container start." >&2
else
    bind "$ws/.devcontainer" /app/.devcontainer true
fi
bind "$ws/.vscode" /app/.vscode true
bind "$ws/.claude/settings.json" /app/.claude/settings.json true
bind "$ws/.claude/settings.local.json" /app/.claude/settings.local.json true
bind "$ws/.mcp.json" /app/.mcp.json true

# Secrets and host-only files: /dev/null over every file matching mask-patterns.txt
# (template defaults next to this script + optional project file; "!" lines allow)
deny="$out.deny"
allow="$out.allow"
cat "$defaults_patterns" ${project_patterns:+"$project_patterns"} | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' > "$out.patterns"
grep -v '^!' "$out.patterns" > "$deny"
sed -n 's/^!//p' "$out.patterns" > "$allow"
while IFS= read -r f; do
    bind /dev/null "/app/$f" true
done < <(find . \( -path ./.git -o -name node_modules \) -prune -o -type f -print 2> /dev/null \
    | sed 's|^\./||' | grep -E -f "$deny" | { if [ -s "$allow" ]; then grep -v -E -f "$allow"; else cat; fi; })
rm -f "$out.patterns" "$deny" "$allow"

# Generated files with interpolated .env values: shared/.env (matches the .env patterns above)
# and the resolved config (written after this script by resolve-config.sh, so mask it explicitly;
# the placeholder makes the mount target exist on the very first start)
resolved="$ws/.devcontainer/.generated/compose.resolved.yml"
[ -e "$resolved" ] || : > "$resolved"
bind /dev/null /app/.devcontainer/.generated/compose.resolved.yml true

if [ -n "$main_git" ]; then
    config="$main_git/config"
    pointer="$ws/.git"
    if [ "$external" = 1 ]; then
        relink "$main_git" /app
        config="$link.config"
        pointer="$link.git"
    fi
    targets="$main_git"
    # Main worktree: the same gitdir is also reachable through the workspace mount
    [ "$main_git" = "$ws/.git" ] && targets="$targets
/app/.git"
    while IFS= read -r t; do
        protect_gitdir "$main_git" "$t" "$config"
        if [ "$self_git" != "$main_git" ]; then
            # Linked worktree: its own gitdir stays writable (HEAD, index), its pointers don't
            name="${self_git#"$main_git"/worktrees/}"
            mkdir -p "$self_git/modules"
            bind "$self_git" "$t/worktrees/$name" false
            for f in commondir gitdir config.worktree; do
                [ -e "$self_git/$f" ] && bind "$self_git/$f" "$t/worktrees/$name/$f" true
            done
            bind "$self_git/modules" "$t/worktrees/$name/modules" true
        fi
    done <<< "$targets"
    # Linked worktree or external gitdir: the .git pointer file in the workspace
    [ -f "$ws/.git" ] && bind "$pointer" /app/.git true
fi

# Allowlisted nested repos: same protection as the main gitdir
while IFS= read -r d; do
    [ -n "$d" ] && protect_gitdir "$d" "/app/${d#"$ws"/}"
done <<< "$nested_gitdirs"
# .git pointer files (submodules, allowlisted): redirecting one changes which gitdir host git uses.
# One into main_git outside the workspace (submodules of a submodule workspace) is relinked.
while IFS= read -r p; do
    [ -n "$p" ] || continue
    src="$ws/$p"
    if [ -n "$main_git" ] && [ "$external" = 1 ]; then
        r="$(resolve_pointer "$ws/$p")"
        case "$r" in
            "$main_git"/*)
                relink "$r" "/app/$(dirname "$p")"
                src="$link.git"
                bind "$link.config" "$r/config" true
                ;;
        esac
    fi
    bind "$src" "/app/$p" true
done <<< "$pointers"
[ "$n" -gt 0 ] && bind "$main_git" "$host_git_view" true

mv "$tmp" "$out"
echo "protect-paths: wrote $out"
