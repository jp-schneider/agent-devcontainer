# Testing changes to the template

Inside the devcontainer, `docker build`/`run` are blocked by design, and the compose plugin isn't
installed. So verification is split between offline checks (runnable inside the container) and
host checks.

## Offline checks

Reference implementations live in the template repo's `.claude/scratchpad/` (not shipped). Each
has a README with the exact command.

| Check | What it proves | Scratchpad entry |
|---|---|---|
| Compose merge equivalence | A refactor of compose files keeps the merged config (approximates compose's merge in Python, `uv run --with pyyaml`) | `*-compose-split-check`, `*-toolchain-split-check` |
| apt package set | Moving packages between Dockerfile and `apt-packages.txt` keeps the set | `*-toolchain-split-check` |
| Host override | `host-override.sh` output for WSL and generic hosts (`PROC_VERSION` test hook) | `*-host-override-check` |
| Template flow | cleanup + two template updates on throwaway repos (`test.sh`, 21 checks) | `*-template-flow-check` |
| Path protection | `protect-paths.sh`: generated read-only binds (main worktree, linked worktree, submodule), planted-repo aborts, allowlist, mask patterns (defaults, project file, allow lines), awkward paths, host-only switch, allowlisted nested repos and pointer files (`test.sh`, 42 checks) | `*-protect-paths-check` |

Tests that create git repos must use a work dir **outside the workspace** (`"$(mktemp -d)/work"`).
Otherwise `protect-paths.sh` finds them as planted repos and aborts the next container start.

Every check should have a **negative control**: a deliberately wrong input that must make it
fail. Otherwise a passing check proves nothing.

Also run `bash -n` on all changed shell scripts. `shellcheck` isn't installed in the image.

## Host checks

After changes to the Dockerfile, compose files or host scripts:

1. **Config:** `bash .devcontainer/shared/initialize.sh <toolchain>`, then
   `docker compose -f … config` with the variant's file list. Check that every `${VAR}` resolved
   and that the expected mounts and args are present.
2. **Rebuild** each affected variant ("Rebuild and Reopen in Container").
3. **Inside the container:**
   - `claude --version` and the toolchain tools (`uv --version`).
   - `ls /usr/lib/wsl` (WSL only).
   - `nvidia-smi` (GPU variants).
   - `env | grep -E 'VSCODE_IPC|GIT_ASKPASS|SSH_AUTH_SOCK'` should print nothing, or only empty values.
   - `docker ps` should fail unless the proxy overlay is enabled.
   - Protection (each write must fail, with "Read-only file system" or "Device or resource busy"):
     `touch /app/.devcontainer/x`, `touch /app/.git/hooks/x`, `git config foo.bar 1`,
     `echo {} > /app/.claude/settings.json`, `mv /app/.vscode /app/v2`.
   - `cat /app/.env` prints nothing; variables from `container.env` are in `env`.
   - A commit still works: `git commit --allow-empty -m test`, then `git reset --soft HEAD~1`.
   - VS Code: Source Control still shows the main repo (with `git.autoRepositoryDetection: false`
     it may need "Git: Open Repository" once; note which), and a planted repo is **not** auto-opened.
   - A planted repo aborts the next start: `git init /app/planted`, then rebuild, then expect
     `protect-paths: ABORT`. Remove the repo afterwards.
4. **Labels** (from the host or via the proxy): the container's `com.docker.compose.project` is
   `<slug>_devcontainer`, and other projects' containers are untouched.

**Migration gotchas** seen when the compose layout changed:
- **Container name in use:** the old container (different project name) blocks the name; fix
  with `docker rm -f claude-code-<worktree>`.
- **Orphaned proxy:** a proxy container left behind after removing the overlay keeps running;
  remove it with `docker rm -f`.

## Cleanup workflow

Only testable on GitHub:
1. Mark the template repo as a template.
2. Create a throwaway repo from it.
3. Within ~2 minutes, expect a "Clean up template files" commit by `github-actions[bot]`.

## Not yet covered

- bash 3.2 (macOS) execution of the host scripts.
- A native Linux and a macOS host.
- The real GitHub Actions run.
