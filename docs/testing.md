# Testing changes to the template

Inside the devcontainer, `docker build`/`run` are blocked by design, and the compose plugin isn't
installed. So verification is split between offline checks (runnable inside the container) and
host checks.

## Automated tests (`tests/`, bats)

Run everything, or one suite:

```bash
tests/run.sh
tests/run.sh tests/protect-paths.bats
BASH_UNDER_TEST=/bin/bash tests/run.sh   # scripts under test with another bash (macOS: 3.2)
```

- **bats-core is a pinned dev dependency:** `tests/run.sh` uses `bats` from `PATH`, otherwise it
  downloads the version pinned in the script into `~/.cache`, outside the workspace, and checks
  the commit SHA.
- **Also needed:** `git`, `jq`, Python 3 with PyYAML. `uv run --with pyyaml` is used if
  PyYAML isn't installed.
- **The `template-dev` variant** has all of this, plus `shellcheck`. Inside it, `tests/run.sh`
  and the CI lint step
  (`git ls-files -z '*.sh' '*.bash' '.devcontainer/shared/bin/*' | xargs -0 shellcheck --severity=warning`)
  run as they are.
- **From VS Code:** *Tasks: Run Test Task* runs all suites; `.vscode/tasks.json` (template only)
  also has tasks for the current file, the selected test name (`--filter`), bash 3.2, and CI's
  shellcheck with findings in the Problems panel.
- **CI** (`.github/workflows/tests.yml`) runs on every push to `main` and on pull requests:
  - Ubuntu: `shellcheck --severity=warning` on all shell scripts, then all suites;
  - macOS: all suites with `/bin/bash` 3.2 as the bash under test, which checks the
    compatibility the host scripts promise.

| Suite | Covers |
|---|---|
| `protect-paths.bats` | read-only binds (main worktree, linked worktree, submodules, allowlisted repos and pointers), planted-repo aborts, secret masks (defaults, project file, `!` exceptions), awkward paths, `DEVCONTAINER_EDITABLE_BY_AGENT` |
| `initialize.bats` | full `initialize.sh` on a repo copy with a fake `docker`: generated files, apt lists, `DEVCONTAINER_*` from `.env`, toolchain vs. `base`, several toolchains (order, missing-overlay warning, unknown toolchain), compose order |
| `resolve-config.bats` | compose file list per variant, failure handling |
| `host-override.bats` | WSL detection (hooks `PROC_VERSION`, `WSL_LIB_DIR`) |
| `variants.bats` | invariants across variants: identical `remoteEnv` and security settings, `initializeCommand`, compose order, socket cleanup, `shared/post-start.sh`, each toolchain's overlay listed |
| `template-flow.bats` | "Use this template" → cleanup → customize → two updates (unrelated histories / tag) |
| `toolchains.bats` | `shared/post-start.sh` dispatch (order, failures); node `init-host.sh`: package dir discovery, generated overlay, mount points, host dirs, skipped paths |
| `gitignore.bats` | `.gitignore`: `.venv` and the uv `.venv-<worktree>.ct` symlinks ignored at any depth; similar names not |
| `adopt.bats` | `--adopt` in a foreign repo: legacy move (content, mode), seeding, `.gitignore` union, remaining conflicts, warnings, then a regular update; refusals |

**Rules for tests:**
- **Work dir outside the workspace** (`setup_workdir` in `tests/helpers.bash`). Tests create git
  repos, which `protect-paths.sh` would treat as planted and abort the next container start on.
- **A negative control per suite:** a deliberately wrong input that must fail. Otherwise a passing suite proves nothing. Try to explicitly handle edge cases, e.g., a missing overlay or toolchain, a planted repo, a missing apt package, a missing compose file, a missing `docker` binary, etc.
- **bash 3.2-safe assertions:** no `! cmd` or `[[ … ]]` mid-test, because they don't fail the
  test. Use `not_grep`, `output_has` and `[ … ]`.
- **Check that a new suite catches bugs:** break the script under test deliberately (one change
  at a time) and confirm the suite fails.

## Host checks

After changes to the Dockerfile, compose files or host scripts:

1. **Config:** `bash .devcontainer/shared/initialize.sh <variant> [<toolchain>...]`, then inspect
   `.devcontainer/.generated/compose.resolved.yml`, or run
   `docker compose -f … config` with the variant's file list. Check that every `${VAR}` resolved
   and that the expected mounts and args are present.
2. **Rebuild** each affected variant ("Rebuild and Reopen in Container").
3. **Inside the container:**
   - `claude --version` and the toolchain tools (`uv --version`; node: `node -v`, `pnpm -v`, `findmnt` on each `node_modules`).
   - `ls /usr/lib/wsl` (WSL only).
   - `nvidia-smi` (GPU variants).
   - `env | grep -E 'VSCODE_IPC|GIT_ASKPASS|SSH_AUTH_SOCK'` should print nothing, or only empty values.
   - `docker` is not installed unless the proxy overlay is enabled (then `docker ps` works).
   - Project packages from `.devcontainer/apt-packages.txt` are installed (`dpkg -l <pkg>`).
   - Protection (each write must fail, with "Read-only file system" or "Device or resource busy"):
     `touch /app/.devcontainer/x`, `touch /app/.git/hooks/x`, `git config foo.bar 1`,
     `echo {} > /app/.claude/settings.json`, `mv /app/.vscode /app/v2`.
   - `cat /app/.env` prints nothing; variables from `container.env` are in `env`.
   - `env | grep -E "HOST_HOME|LOCAL_WORKSPACE_FOLDER|GIT_MAIN_REPO_PATH"` prints nothing, while `UV_PROJECT_ENVIRONMENT` is set.
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
