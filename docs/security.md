# Security model

**Goal:** an agent running inside the container, possibly steered by prompt injection or
malicious dependencies, should not be able to act on the host or on remote accounts beyond the
workspace it was given.

**This is best-effort hardening, not a guarantee.** It reduces the blast radius; it doesn't make
running an agent risk-free. The sections below say what is covered and what is not.

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

**LM Studio overlays (opt-in).** `claude-local` runs the same Claude Code client, so every
protection here applies unchanged. A local model may follow injected instructions more readily, which
is exactly the case these protections are for. What the overlays add:
- **Host mode** (`compose.lmstudio-host.yml`): `extra_hosts` adds the *name* `host.docker.internal`.
  Without egress filtering the host gateway was already reachable by IP, so this adds no capability.
  It does mean the host LM Studio server is reachable by the agent, which is the point. Bind it
  to the Docker bridge rather than `0.0.0.0` (LAN) and turn on authentication. The token sits in
  `container.env`, so the agent can read it: it can use the server, nothing more.
- **Sidecar mode** (`compose.lmstudio-sidecar.yml`): the `lmstudio` container has the core's
  hardening (`cap_drop: ALL`, `no-new-privileges`, non-root host UID), no published port and no
  auth. The agent can call its whole API. If that API can download models (not verified), the agent can
  write into the bind-mounted host models folder. That folder holds model weights, not code the host executes. The image fetches llmster from `llmster.lmstudio.ai` at a pinned
  version and checks a pinned SHA-512. It does not run `install.sh`, which picks the CPU-only
  bundle when no GPU is visible during the build and trusts a checksum served by the same host.

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
| `/app/.git` (linked worktree, submodule workspace) | pointer file; redirecting it changes which gitdir host git uses | read-only (submodule workspace: a generated pointer, see below) |
| `.claude/settings.json`, `.claude/settings.local.json`, `.mcp.json` | hooks and MCP servers run when Claude Code runs **on the host**; permission rules | read-only; in-container "always allow" approvals don't persist |
| `.vscode/` | tasks (`runOn: folderOpen`), interpreter and terminal settings in the host VS Code | read-only |
| the above in known nested repos: `<dir>/.devcontainer/`, `<dir>/.vscode/`, `<dir>/.claude/settings*.json`, `<dir>/.mcp.json` | the nested repo can be opened on the host on its own (devcontainer, VS Code, Claude Code) | read-only; the rest of `<dir>/.claude/` stays writable |
| files matching `mask-patterns.txt` (anywhere in the workspace): `.env*`, `*.env`, private keys, `.netrc`/`.npmrc`/`.pypirc`, cloud credentials, `secrets.*`, tfvars/tfstate | host-only config and secrets | masked with `/dev/null` (empty, read-only). The host copy is untouched. Exceptions: `container.env`, `.env.example/.sample/.template`, the generated `shared/.env` |

The main gitdir is reachable at **two** container paths in the main worktree: its absolute host
path (worktree support mount) and `/app/.git`. Both are covered.

**Workspace that is a submodule:** its gitdir `<super>/.git/modules/<name>` is mounted at its host
path; the superproject isn't. Its relative `.git` pointer and `core.worktree` don't resolve from
`/app`, so `/app/.git` and the gitdir's `config` are read-only binds of generated files
(`.devcontainer/.generated/git-links/`, inside the read-only `.devcontainer/`). The generated
`config` includes the host config through a read-only bind of the whole gitdir at
`/opt/host-gitdir` (a directory bind, so host edits stay visible), then sets `core.worktree`.
Nested submodules' pointers and configs are replaced the same way. Nothing becomes writable that
isn't for a normal repo.

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
- **Their host-trusted paths too.** A nested repo can be opened on the host on its own: as a
  devcontainer (its `initializeCommand` runs on the host), in VS Code, with Claude Code. So its
  `.devcontainer/` (always; `DEVCONTAINER_EDITABLE_BY_AGENT` applies to the workspace only),
  `.vscode/`, `.claude/settings*.json` and `.mcp.json` are read-only, with the same placeholders.
  Placeholder directories are empty, which git ignores; placeholder files show as untracked in the
  nested repo. That is the price for having no gap: without them the agent could create the file.
- **Unknown nested repos abort the container start.** These are exactly the ones planted since the
  allowlist was last approved on the host.
- **Creating repos can't be prevented** on a read-write mount: `git init`, `clone`, `mkdir .git`
  and unpacking an archive all work. The agent is instructed to clone into `/tmp` (inside the
  container only). Detection happens at the next start; see "Known limitations" for the gap in between.
- **Old-style submodules:** ones with a `.git` *directory* need `git submodule absorbgitdirs` once.

**Secret files, two more layers on top of masking:**
- **Claude Code deny rules:** `.claude/settings.json` starts from
  `.devcontainer/shared/claude-settings.default.json`, with `Read(...)`/`Edit(...)` deny rules for
  the same files as globs. `protect-paths.sh` copies it if the file is missing. In the container
  this only saves pointless reads. **On the host** it keeps a Claude Code session from reading the
  real secrets. Limits:
  - Read rules govern Claude's file tools; a shell command like `cat .env` is not reliably covered.
  - Globs can't express exceptions, so `.env.example` is denied too.
- **Container VS Code `files.exclude`** (in each variant's `devcontainer.json`, not
  `.vscode/settings.json`, which the host shares): hides the masked files in the Explorer. This is
  cosmetic only. `*.env` isn't listed, because it would also hide `container.env`.
- **Three lists to keep in sync:** `mask-patterns.txt` (regex, the actual protection), the deny
  rules, and `files.exclude`.

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
- **`.env`** is host-only. `initialize.sh` copies only its `DEVCONTAINER_*` lines, unchanged, into
  `shared/.env`, as `${DEVCONTAINER_*}` for compose files. The prefix rules out collisions with
  compose's own `COMPOSE_*` settings and the generated keys. `shared/.env` is masked
  too (it matches the `.env` pattern). A value only reaches the container if a compose file
  references it (a mount path, or `environment:`).
  Because the agent can't write it, those values are trusted.

## What the container can see about the host (not confidential)

The protections above are about **integrity** (the agent can't change what the host runs) and
**secret files** (masked). Host paths and the shape of the setup are **not** hidden, and can't
be hidden with this design:
- **`/proc/self/mountinfo`** lists every bind mount with its host source path: home directory,
  repo path, volume paths. It also shows which files are masked (`/null -> /app/.env`). Every
  process can read it, and Docker doesn't mask it.
- **Absolute host paths in the container are unavoidable:** the common gitdir is mounted at
  its real host path so git worktrees and submodule workspaces resolve.
- **The generated overlays are readable:** `.devcontainer/.generated/compose.{host,protect}.yml`.
  `shared/.env` and `compose.resolved.yml` are masked, because they contain interpolated `.env` values.

So masking these files wouldn't add confidentiality, which is why they stay visible. Don't
encode secrets in paths or directory names.

**Environment variables:**
- **Passed in:** only `container.env` (`env_file`) plus variables an overlay passes explicitly
  (e.g. `UV_VENVS_ROOT`, `UV_PROJECT_ENVIRONMENT` from `toolchains/uv/compose.yml`).
- **Not passed in:** the host-side values in `shared/.env` (`HOST_HOME`, `HOST_UID`/`GID`,
  `LOCAL_WORKSPACE_FOLDER`, `GIT_COMMON_DIR`, `WORKTREE_NAME`, `PROJECT_SLUG`,
  everything copied from `.env`). They are only used for compose interpolation. This is tidiness, not
  confidentiality: see above.

## Known limitations

The list lives in [.devcontainer/README.md](../.devcontainer/README.md#known-limitations), so derived
repos keep it (this folder is removed by the cleanup). Update it there.

## Maintaining

Treat changes to `remoteEnv`, `security-harden.sh`, `compose.core.yml`, `protect-paths.sh` and the socket cleanup as
security-relevant. They are duplicated in every variant's `devcontainer.json` (`remoteEnv`), so
keep all variants in sync.
