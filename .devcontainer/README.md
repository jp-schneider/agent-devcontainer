# Devcontainer

A hardened development container for running coding agents (Claude Code) with limited blast
radius: no root, all capabilities dropped, no SSH/GPG agent, VS Code escape hatches cleared, and
no Docker socket by default.

## Choosing a variant

Each folder with a `devcontainer.json` is one variant. VS Code ("Reopen in Container") and the
devcontainer CLI ask which one to use. Delete the variants you don't need.

| Variant | Base image | Toolchain | GPU |
|---|---|---|---|
| `python-uv-gpu` | `nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04` | uv (+ ruff, ty) | yes |
| `python-uv-cpu` | `ubuntu:24.04` | uv (+ ruff, ty) | no |

All variants of a worktree share one container name, so switching variants replaces the container.

## How it is composed

A variant is a list of compose files, merged in order:

```
shared/compose.core.yml          always first: hardening, workspace, Claude config, network
shared/compose.gpu.yml           optional: NVIDIA GPU + CUDA base image
shared/compose.docker-proxy.yml  optional: read-only Docker API (see below)
shared/toolchains/<name>/compose.yml   toolchain build arg + volumes
../.generated/compose.host.yml   always last: generated per host by initialize.sh
```

- **`shared/Dockerfile`**: one Dockerfile for all variants, parametrized by `BASE_IMAGE` and `TOOLCHAIN`.
- **`shared/initialize.sh <toolchain>`**: runs on the host before every start. It writes
  `shared/.env` with paths, UID/GID and the compose project name. It also runs the toolchain's
  `init-host.sh` and generates the host overlay.
- **`compose.core.yml` must stay first:** compose loads `.env` from the first file's directory.

### Optional: Docker access

Add `"../shared/compose.docker-proxy.yml"` to a variant's `dockerComposeFile` (before the host
overlay) to give the agent read-only Docker access (`ps`, `logs`, `inspect`; no `run`/`exec`/`build`).
It's off by default because `docker inspect` exposes the environment variables of **every**
container on the host. Never mount `/var/run/docker.sock` directly instead.

## Hosts

| Host | Notes |
|---|---|
| WSL2 (Windows) | `/usr/lib/wsl` is mounted automatically (GPU driver libraries). |
| Native Linux | GPU variants need the NVIDIA container toolkit. |
| macOS | CPU variants only. `initialize.sh` is bash 3.2 compatible. |

Host detection lives in `shared/host-override.sh`. Its output (`.devcontainer/.generated/`)
is gitignored.

## Toolchains

A toolchain is a folder `shared/toolchains/<name>/`. Every file in it is optional:

| File | Runs | Purpose |
|---|---|---|
| `apt-packages.txt` | image build, as root | system packages, one or more per line, `#` comments |
| `install.sh` | image build, as the container user | user-level tools |
| `init-host.sh <env-file>` | host, before start | append env vars, create shared volumes |
| `post-start.sh` | container start | e.g. link venvs into volumes (called from `postStartCommand`) |
| `compose.yml` | — | overlay that sets `build.args.TOOLCHAIN` and adds volumes |

To add one (e.g. `conda`):
1. Create the folder.
2. Add a variant whose `dockerComposeFile` lists its `compose.yml` and whose `initializeCommand`
   passes the toolchain name to `initialize.sh`.

For conda, use Miniforge (conda-forge), not the Anaconda `defaults` channel, which has commercial terms.

### uv details

- **Venvs:** they live in a per-worktree volume. `post-start.sh` symlinks
  `<project>/.venv-<worktree>.ct` into it for every `pyproject.toml` under `/app`, and
  `UV_PROJECT_ENVIRONMENT` points uv at that link.
- **uv's Python installs:** they're shared across all projects in the external volume
  `claude-code-uv-python-versions`, which `init-host.sh` creates.

## Claude Code

Claude Code is installed at image build time. Rebuild the container to update it. Its config
persists in the volume `claude-code-<worktree>-config`.

## Updating from the template

Repos created with "Use this template" have no shared git history with the template. To pull
template updates:

```bash
bash .devcontainer/update-from-template.sh   # optional: <template-url> <branch>
```

- **Merge behaviour:** it merges `template/main` without committing, keeps this repo's own
  `CLAUDE.md`, `README.md` and `.claude/`, and drops template-only files.
- **First run:** expect conflicts in every template file you have changed, or that the template
  has changed since you created the repo. That's because there is no common ancestor yet.
  Later updates merge normally.
- **Deleted variants:** variants you deleted come back if the template changed them. Delete them again.

## First-time setup of repos created from the template

After "Use this template", the workflow `.github/workflows/template-cleanup.yml` replaces the
template's `CLAUDE.md`, `README.md` and `.claude/` history with fresh files. It runs within a
minute or two of creation; refresh the page.

If it didn't run, or couldn't push (Settings → Actions → General → Workflow permissions must
allow "Read and write"), run it by hand and commit:

```bash
bash .github/template-cleanup/cleanup.sh
```

The workflow file stays behind as a no-op.
