# Extending the template

## Add a variant

1. Copy an existing variant folder, e.g. `.devcontainer/python-uv-cpu/` → `.devcontainer/<new>/`.
2. In its `devcontainer.json`:
   - `name`: shown in the VS Code picker.
   - `dockerComposeFile`: keep `../shared/compose.core.yml` first, `../compose.project.yml` after
     the template overlays, then
     `../.generated/compose.host.yml`, and **`../.generated/compose.protect.yml` last**. Otherwise
     a later file could override a protected mount.
   - `initializeCommand`: `["bash", ".devcontainer/shared/initialize.sh", "<variant>", "<toolchain>", …]`,
     zero or more toolchains in install order. The variant name must match the folder;
     `resolve-config.sh` reads the compose list from it. List each toolchain's `compose.yml` (and
     any overlay it generates, e.g. `../.generated/compose.node.yml`) before `compose.project.yml`.
   - `postStartCommand`: starts with `bash /app/.devcontainer/shared/post-start.sh;` (runs the
     toolchains' `post-start.sh`). Keep the socket cleanup.
   - `customizations.vscode.extensions`: stack-specific extensions.
3. **Keep `remoteEnv` and the VS Code security settings identical to the other variants.**
   devcontainer.json has no include mechanism, so these are duplicated
   (see [security.md](security.md)).
4. Adjust the variant's `apt-packages.txt`: Python variants ship the OpenCV runtime, other stacks
   usually don't need it.
5. Add the variant to the table in `.devcontainer/README.md`.

## Add a toolchain

Create `.devcontainer/shared/toolchains/<name>/`. Every file is optional:

| File | Runs | Notes |
|---|---|---|
| `apt-packages.txt` | build, root | Whitespace-separated packages, `#` comments |
| `install.sh` | build, container user | Create volume mount points under `$HOME` here, so fresh volumes are user-owned |
| `init-host.sh <env-file>` | host, before start | Append env vars; `docker volume create` shared volumes; mount points under `/app` go to `.generated/mountpoints.txt`. **bash 3.2** |
| `post-start.sh` | container start, via `shared/post-start.sh` | Must be idempotent; a failure is reported, not fatal |
| `compose.yml` | — | Volumes and environment. The toolchain list comes from `initializeCommand`, not from here |

Checklist:
- **Volumes:** new volumes are named `${RESOURCE_PREFIX:-agent-sandbox}-…`:
  per worktree `…-${WORKTREE_NAME:-project}-<what>`, shared `…-<toolchain>-<what>`. Existing
  `claude-code-…` volumes keep their names. Volumes shared across projects are `external: true` and
  created in `init-host.sh`. Compose would otherwise label them with whichever project created
  them first.
- **Volumes under `/app`** (mounted over the bind mount): append the target to
  `.devcontainer/.generated/mountpoints.txt` in `init-host.sh` and create the host directory, so
  both the image's and the host's mount point are user-owned (see
  [architecture.md](architecture.md#image-build)).
- **Toolchain-specific state:** don't put it in core; core must stay toolchain-agnostic.
- **apt packages:** only what the toolchain itself needs. Project-specific packages (OpenCV,
  CUDA extensions, …) belong in the project's `.devcontainer/apt-packages.txt`.
- **Environment variables:** `init-host.sh` writes them to `shared/.env`, which is **not** passed
  into the container. Pass the ones the container needs explicitly in the toolchain's `compose.yml`
  (`environment: {VAR: ${VAR}}`).
- **Combinable:** a toolchain must work next to others (e.g. uv + node). Don't assume it is
  alone in `.bashrc`, `PATH` or apt; `install.sh` runs after those of earlier toolchains.

Notes for planned toolchains:
- **conda:** Miniforge (conda-forge), **not** Anaconda's `defaults` channel (commercial terms).
  Persist `CONDA_ENVS_PATH` and `CONDA_PKGS_DIRS` in volumes.
- **pyenv + poetry:** persist `$PYENV_ROOT/versions`. Set `POETRY_VIRTUALENVS_PATH` to a volume;
  no symlinks are needed.
- **Playwright** (with node): persist browsers (`~/.cache/ms-playwright`) in a shared volume.

## Add an overlay

Put it in `.devcontainer/shared/compose.<feature>.yml` and document it in
`.devcontainer/README.md`. Constraints:
- An overlay must not repeat a mount target that core defines, or it replaces core's mount.
- An overlay must not mount anything at or below a protected path (see [security.md](security.md)).
- New secret-file patterns: add them to `mask-patterns.txt` (regex) and, as globs, to
  `claude-settings.default.json` and the variants' `files.exclude`.
  New host-executed paths belong in `protect-paths.sh`, not in an overlay.
- Services it adds should join the `dev` network.

## Override the base image for one variant

There is no per-variant hook yet. Add a compose file in the variant's folder:

```yaml
# .devcontainer/<variant>/compose.variant.yml
services:
  claude-code:
    build:
      args:
        BASE_IMAGE: nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04
        IMAGE_VERSION: cuda-12.4.1-cudnn-ubuntu22.04
```

List it after `compose.gpu.yml`. The image must be Debian/Ubuntu-based.

## Agent-facing docs

`.devcontainer/shared/devcontainer.md` describes the environment to the agent. The generic
`CLAUDE.md` imports it with `@.devcontainer/shared/devcontainer.md`. When an overlay changes what
the agent can do (like the Docker proxy), add a separate `devcontainer.<feature>.md` and point to
it, rather than stating the capability unconditionally.
