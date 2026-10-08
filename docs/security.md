# Security model

**Goal:** an agent running inside the container, possibly steered by prompt injection or
malicious dependencies, should not be able to act on the host or on remote accounts beyond the
workspace it was given.

## Layers

| Threat | Mitigation | Where |
|---|---|---|
| Privilege escalation in the container | non-root user, no sudo, `cap_drop: ALL`, `no-new-privileges` | Dockerfile, `compose.core.yml` |
| Container escape via the Docker API | no Docker socket; optional proxy blocks `run`/`exec`/`build`/`commit` | `compose.docker-proxy.yml` |
| Running commands on the host through VS Code IPC | `VSCODE_IPC_HOOK_CLI`, `REMOTE_CONTAINERS_*` unset; IPC sockets deleted | `remoteEnv`, `security-harden.sh`, `command` loop, `postStartCommand` |
| Using host Git credentials / pushing | `GIT_ASKPASS`/`VSCODE_GIT_*` unset; `dockerCredentialHelper` and `copyGitConfig` off; no SSH keys mounted, `SSH_AUTH_SOCK` emptied | `remoteEnv`, `security-harden.sh`, VS Code settings |
| GPG agent, browser, Wayland | `GPG_AGENT_INFO`, `BROWSER`, `WAYLAND_DISPLAY` cleared | same |

**Why the hardening exists in three places:**
- VS Code re-injects some variables after `remoteEnv` is applied. So
  `~/.config/security-harden.sh`, sourced as the first line of `.bashrc` (before the
  interactive guard, so non-interactive shells such as Claude Code's get it too), is the real
  safeguard.
- The socket cleanup runs in the compose `command` loop rather than `postAttachCommand`, because
  VS Code's lifecycle cleanup kills background processes started from the latter.

**Docker proxy trade-off.** Even read-only access with `CONTAINERS=1` lets the agent
`docker inspect` every container on the host, including environment variables and therefore any
secrets passed that way. It is therefore opt-in per variant. The image is pinned by digest.

## Protected paths (host execution)

**The threat:** the workspace (`/app`) and the main repo's `.git` are bind-mounted read-write. Some
files in them are later **executed or trusted on the host**. If the agent could change them, it
could escape the container the next time you start it or use git there.

**The mechanism:**
- [protect-paths.sh](../.devcontainer/shared/protect-paths.sh) runs on the host (from
  `initialize.sh`) before every start.
- It generates `.devcontainer/.generated/compose.protect.yml`, listed **last** in every variant,
  so its mount targets win.
- The script is trusted because it sits under `.devcontainer/`, which is itself read-only inside
  the container.
- The agent has no `CAP_SYS_ADMIN`, so it can't unmount or remount. Renaming a mount point fails
  with `EBUSY`.

| Path (inside the container) | Why | Effect for the agent |
|---|---|---|
| `/app/.devcontainer/` | scripts run on the host; compose files can grant `privileged`, host mounts | read-only |
| `.git/hooks/`, `.git/config` | hooks, `core.hooksPath`, `core.fsmonitor`, filters, aliases run on the host | read-only. Commits work; `git config`, `push -u`, tracking branches and `submodule init` fail |
| `.git/modules/` | submodule gitdirs have their own hooks/config | read-only; the agent can't commit **inside** submodules |
| `.git/worktrees/` | `commondir`/`gitdir` redirect a worktree's git to another gitdir | read-only, except the current worktree's own entry (its `commondir`, `gitdir`, `config.worktree`, `modules/` stay read-only); `git worktree add` fails |
| `/app/.git` (linked worktree) | pointer file; redirecting it changes which gitdir host git uses | read-only |
| `.claude/settings.json`, `.claude/settings.local.json`, `.mcp.json` | hooks and MCP servers run when Claude Code runs **on the host**; permission rules | read-only; in-container "always allow" approvals don't persist |
| `.vscode/` | tasks (`runOn: folderOpen`), interpreter and terminal settings in the host VS Code | read-only |
| files matching `mask-patterns.txt` (anywhere in the workspace): `.env*`, `*.env`, private keys, `.netrc`/`.npmrc`/`.pypirc`, cloud credentials, `secrets.*`, tfvars/tfstate | host-only config and secrets | masked with `/dev/null` (empty, read-only). The host copy is untouched. Exceptions: `container.env`, `.env.example/.sample/.template`, the generated `shared/.env` |

The main gitdir is reachable at **two** container paths in the main worktree: its absolute host
path (worktree support mount) and `/app/.git`. Both are covered.

**Placeholders:** paths that don't exist yet can't be mounted read-only, so the script creates
them first: an empty `.vscode/`, `.claude/settings*.json` = `{}`, `.mcp.json` =
`{"mcpServers": {}}`, `.env`, and `.git/{hooks,modules,worktrees}/`.

**Template development switch:** `DEVCONTAINER_EDITABLE_BY_AGENT=1` in `.env` (host-only, so the
agent can neither read nor set it) leaves `.devcontainer/` writable. Every start prints a warning.
This **removes the trust anchor**: the agent can then change what runs on the host at the next
start. Use it only in the template repo, and review `git diff -- .devcontainer` before restarting.
All other protections stay in place.

**Nested repositories:** host git run inside a nested repo uses *that* repo's hooks and config.
It does so automatically, too: host VS Code detects repos in subfolders, and git-aware prompts run
`git status`, which executes e.g. `core.fsmonitor`.
- **Known nested repos are protected like the main repo.** Known means a submodule (pointer into a
  read-only `modules/`) or a directory listed in `.devcontainer/allowed-nested-git.txt`, which is
  read-only to the agent. Their `hooks/`, `config`, `modules/` and `worktrees/` are read-only. So
  are all `.git` pointer files, including the gitdir of an allowlisted pointer if it lies in the workspace.
- **Unknown nested repos abort the container start.** These are exactly the ones planted since the
  allowlist was last approved on the host.
- **Creating repos can't be prevented** on a read-write mount: `git init`, `clone`, `mkdir .git`
  and unpacking an archive all work. The agent is instructed to clone into `/tmp` (inside the
  container only). Detection happens at the next start; see "Known limitations" for the gap in between.
- **Old-style submodules:** ones with a `.git` *directory* need `git submodule absorbgitdirs` once.

**Env files:**
- **`container.env`** (repo root, gitignored) is the only file passed into the container
  (`env_file`). Its contents are visible to the agent by design.
**Mask patterns:**
- `.devcontainer/shared/mask-patterns.txt` holds the template defaults; an optional
  `.devcontainer/mask-patterns.txt` holds project additions and exceptions.
- Format: one POSIX ERE per line (`grep -E`), matched against the workspace-relative path. `!`
  lines are allow patterns and win.
- Both files are read-only to the agent. With `DEVCONTAINER_EDITABLE_BY_AGENT=1` the agent could
  edit them to unmask files at the next start.
- `.git/` and `node_modules/` aren't scanned, and symlinks aren't masked.
- A missing defaults file aborts the start.
- **`.env`** is host-only. `initialize.sh` reads `DEVCONTAINER_DATA_PATH`/`RUNS_PATH` from it.
  Because the agent can't write it, those values are trusted.

## What the container can see about the host (not confidential)

The protections above are about **integrity** (the agent can't change what the host runs) and
**secret files** (masked). Host paths and the shape of the setup are **not** hidden, and can't
be hidden with this design:
- **`/proc/self/mountinfo`** lists every bind mount with its host source path: home directory,
  repo path, volume paths. It also shows which files are masked (`/null -> /app/.env`). Every
  process can read it, and Docker doesn't mask it.
- **Absolute host paths in the container are unavoidable:** the main repo's `.git` is mounted at
  its real host path so git worktrees resolve.
- **Generated files are readable:** `.devcontainer/shared/.env` (paths, UID/GID, project name)
  and `.devcontainer/.generated/*.yml` (overlays, resolved config).

So masking these files wouldn't add confidentiality, which is why they stay visible. Don't
encode secrets in paths or directory names.

**Environment variables:**
- **Passed in:** only `container.env` (`env_file`) plus variables an overlay passes explicitly
  (e.g. `UV_VENVS_ROOT`, `UV_PROJECT_ENVIRONMENT` from `toolchains/uv/compose.yml`).
- **Not passed in:** the host-side values in `shared/.env` (`HOST_HOME`, `HOST_UID`/`GID`,
  `LOCAL_WORKSPACE_FOLDER`, `GIT_MAIN_REPO_PATH`, `WORKTREE_NAME`, `PROJECT_SLUG`,
  `DEVCONTAINER_*_PATH`). They are only used for compose interpolation. This is tidiness, not
  confidentiality: see above.

## Known limitations

These are **not** covered by the current setup.

1. **Anything you deliberately run on the host from this repo** is untrusted code the agent may
   have written: `make`, `npm`/`uv run`, `pytest`, `pre-commit`, build backends, `.envrc` (direnv
   asks for re-approval after a change), JetBrains run configurations, and so on. Review the
   diff first, or run them in the container.
2. **Protection is a snapshot at start.**
   - Secret files created during a session aren't masked until the next start. The agent created
     those itself.
   - Worktrees nested inside the workspace are treated as planted repos.
   - **A repo planted during a session** is only caught at the next start. Until then, host tools
     that enter it run its config: host VS Code with the folder opened locally (not attached), or a
     host shell with a git-aware prompt. VS Code attached to the container runs git inside the
     container and is not affected. Avoid host-side git use in the workspace between an agent
     session and the next start.
     *Mitigation:* the template ships `.vscode/settings.json` with
     `"git.autoRepositoryDetection": false` (read-only for the agent), so host VS Code doesn't
     auto-open repos it finds in subfolders. This doesn't cover git-aware shell prompts, other
     IDEs, or user settings that override it. A side effect is that VS Code doesn't auto-detect
     nested repos inside the container either; use "Git: Open Repository" when needed.
3. **Single-file mounts pin the inode.** If the host replaces `.git/config` or a settings file
   (git and Claude Code write by rename), the container keeps seeing the old version until restart.
4. **No egress restriction.** The container has unrestricted outbound network access, so
   workspace data and `container.env` can be exfiltrated. Accepted for now.
5. **The IPC socket cleanup is time-bounded.** The `command` loop runs 10 × 30 s. Sockets that VS
   Code creates later rely on `security-harden.sh` having cleared the variables that point to them.
6. **Image supply chain.** The base images and the uv/Claude installers are fetched at build time
   (tags, `curl | sh`). Only the proxy image is pinned by digest.

## Maintaining

Treat changes to `remoteEnv`, `security-harden.sh`, `compose.core.yml`, `protect-paths.sh` and the socket cleanup as
security-relevant. They are duplicated in every variant's `devcontainer.json` (`remoteEnv`), so
keep all variants in sync.
