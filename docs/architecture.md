# Architecture

## Start-up sequence

What happens when VS Code ("Reopen in Container") or the devcontainer CLI opens a variant:

1. **Host: `initializeCommand`.** It runs `bash .devcontainer/shared/initialize.sh <variant> <toolchain>`
   from the workspace root. The script:
   - creates empty `.env` (host-only; its `DEVCONTAINER_*` lines become compose variables) and
     `container.env` (passed to the container) if missing;
   - rewrites `.devcontainer/shared/.env`: the `DEVCONTAINER_*` lines of `.env` (unchanged), then `WORKTREE_NAME`, `PROJECT_SLUG`,
     `GIT_MAIN_REPO_PATH`, `LOCAL_WORKSPACE_FOLDER`, `HOST_HOME`, `HOST_UID`, `HOST_GID`;
   - runs `toolchains/<toolchain>/init-host.sh .devcontainer/shared/.env` if it exists. For uv it
     appends `UV_*` and runs `docker volume create claude-code-uv-python-versions`;
   - runs `host-override.sh`, which writes `.devcontainer/.generated/compose.host.yml`;
   - runs `protect-paths.sh`, which writes `.devcontainer/.generated/compose.protect.yml` (read-only
     binds; see [security.md](security.md)). If it finds a planted nested repo, it **aborts the
     start**: the script exits non-zero and leaves no overlay, so compose can't start either;
   - runs `resolve-config.sh <variant>`, which writes `.devcontainer/.generated/compose.resolved.yml`:
     `docker compose config` over the variant's `dockerComposeFile` list, read from its
     `devcontainer.json`. It is for inspection only; failures only warn;
   - creates `.claude-docker/.bash_history` and `.claude-docker/.claude.json` for the bind mounts.
2. **Host: compose.** The CLI merges the files in the variant's `dockerComposeFile` list, builds
   the image if needed, and starts the `claude-code` service (plus `docker-proxy` if that overlay
   is listed).
3. **Container: `command`.** `sleep infinity`, plus a background loop that deletes VS Code IPC
   sockets for the first 5 minutes (see [security.md](security.md)).
4. **Container: `postStartCommand`.** It runs the toolchain's `post-start.sh` (uv: venv linking),
   then deletes the SSH-agent and remote-containers sockets created before VS Code attaches.

## Compose composition

A variant is an ordered list of compose files:

```
shared/compose.core.yml                 always first
shared/compose.gpu.yml                  optional
shared/compose.docker-proxy.yml         optional
shared/toolchains/<name>/compose.yml    toolchain
.devcontainer/compose.project.yml       project-owned: mounts, services, resources
../.generated/compose.host.yml          generated: host-specific mounts
../.generated/compose.protect.yml       generated, always last: read-only protection
```

Merge rules that matter here:
- **Mappings merge recursively, and for the same key the later file wins.** This applies to
  `build.args` and `environment`.
- **Service `volumes` merge by mount target.** Overlays add mounts; they never replace core's.
- **Top-level `volumes`/`networks` merge by name.**

### Constraints

**`compose.core.yml` must be first.** Compose's project directory is the directory of the first
file, and compose auto-loads `.env` from there for `${VAR}` interpolation. That is why the
generated `.env` lives in `shared/` and not in `.devcontainer/` or `.generated/`.
It is used for interpolation only; `env_file` passes just `container.env`, and overlays add the
variables the container needs via `environment:` (e.g. the uv overlay's `UV_*`).

**The project name is pinned:** `name: ${PROJECT_SLUG}_devcontainer`.
- *Why:* without it, the devcontainer CLI derives the name from the first file's directory
  (`shared`), so every project built from the template would share one compose project.
  Rebuilding one would then recreate another's container.
- *How:* `PROJECT_SLUG` is the workspace folder name, lowercased, with everything except
  `[a-z0-9_-]` removed. This reproduces the CLI's previous default
  (`<workspace>_devcontainer`), so existing volumes and networks kept their labels.
- *Known gap:* compose requires the name to start with a letter or digit, so a folder named
  `_foo` or `-foo` fails.

**Names derived from the worktree.** Container `claude-code-<worktree>`, network `<worktree>-dev`,
volumes `claude-code-<worktree>-{config,virtualenvs}`.
- Each git worktree gets its own container and state.
- All variants of one worktree share a container name, so switching variants replaces the container.

## Image build

One [Dockerfile](../.devcontainer/shared/Dockerfile) serves all variants. It is parametrized by
build args that the overlays set:

| Arg | Default | Set by |
|---|---|---|
| `BASE_IMAGE` | `ubuntu:24.04` | `compose.gpu.yml` → `nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04` |
| `IMAGE_VERSION` | `ubuntu24.04` | `compose.gpu.yml` (image label only) |
| `TOOLCHAIN` | `none` | `toolchains/<name>/compose.yml` |
| `DOCKER_CLI` | `0` | `compose.docker-proxy.yml` → `1` (the Docker CLI is useless without the proxy) |
| `USER_UID` / `USER_GID` | `1000` | `compose.core.yml`, from `HOST_UID`/`HOST_GID` |

**Base image resolution:** the Dockerfile default, unless an overlay in the list sets
`BASE_IMAGE`; later files win. `python-uv-gpu` gets CUDA from `compose.gpu.yml`.
`python-uv-cpu` doesn't list that overlay and gets `ubuntu:24.04`. The base must be
Debian/Ubuntu-based (the Dockerfile uses `apt-get`, `locale-gen`, `usermod`).

Build order:
1. Core apt packages.
2. Docker CLI, only if `DOCKER_CLI=1`; then the toolchain's `apt-packages.txt`; then the project and
   variant packages (`.generated/apt-packages.txt`, see below); all as root.
3. Locale.
4. User creation, matching the host UID/GID. This renames an existing user/group with that ID,
   e.g. `ubuntu` (1000) on Ubuntu 24.04 images, or `dialout` (GID 20) on macOS hosts.
5. `security-harden.sh`.
6. Claude Code (native installer).
7. The toolchain's `install.sh`, as the user.

**Build context** is `.devcontainer/` (`dockerfile: shared/Dockerfile`), so the project's package
lists are reachable. `.devcontainer/.dockerignore` sends only `shared/Dockerfile`,
`shared/toolchains/` and `.generated/apt-packages.txt`, which keeps generated files with inlined
`container.env` and `.env` files out of the build.

**Project and variant packages.** `initialize.sh <variant>` merges `.devcontainer/apt-packages.txt`
(all variants) and `.devcontainer/<variant>/apt-packages.txt` into `.generated/apt-packages.txt`:
comments stripped, one package per line. The file is always written, possibly empty, so the
Dockerfile can `COPY` it unconditionally. `pkg=version` pins go to `apt-get` as-is.

`COPY shared/toolchains/` copies all toolchains, so editing any toolchain invalidates the cache from
that layer on for every variant. That's acceptable at the current size.

## Host-specific configuration

[host-override.sh](../.devcontainer/shared/host-override.sh) runs on the host and writes
`.devcontainer/.generated/compose.host.yml`:
- **WSL2** (the kernel version contains "microsoft" **and** `/usr/lib/wsl` exists): mounts
  `/usr/lib/wsl:ro`, which carries the GPU driver libraries from the Windows NVIDIA driver.
- **Anything else:** `services: {}`.
  - The mount must not be unconditional. On native Linux, Docker would create an empty
    root-owned `/usr/lib/wsl` on the host (`create_host_path: true`). On macOS the path isn't shared.

`initialize.sh`, `host-override.sh` and `init-host.sh` run on the host, so they must stay
**bash 3.2 compatible** (macOS system bash): no `mapfile`, `${var,,}`, associative arrays,
or `${arr[@]}` on empty arrays under `set -u`.

## Persistence

| What | Where | Lifetime |
|---|---|---|
| Workspace | bind mount `/app` | host |
| Main repo `.git` (worktree support) | bind mount at the same absolute path | host |
| Claude config | volume `claude-code-<worktree>-config` | per worktree |
| Claude account state, bash history | bind mounts from `.claude-docker/` (gitignored) | per worktree, on host |
| uv venvs | volume `claude-code-<worktree>-virtualenvs`, symlinked from `<project>/.venv-<worktree>.ct` | per worktree |
| uv Python installs | external volume `claude-code-uv-python-versions` | shared by all projects |
| Claude Code binary | image layer | until rebuild |

The `.venv-<worktree>.ct` link name doesn't collide with a `.venv` created on the host, and it
differs between worktrees. `UV_PROJECT_ENVIRONMENT` points uv at it.
