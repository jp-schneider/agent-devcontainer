# Extending the template

## Add a variant

1. Copy an existing variant folder, e.g. `.devcontainer/python-uv-cpu/` → `.devcontainer/<new>/`.
2. In its `devcontainer.json`:
   - `name`: shown in the VS Code picker.
   - `dockerComposeFile`: keep `../shared/compose.core.yml` first, then
     `../.generated/compose.host.yml`, and **`../.generated/compose.protect.yml` last**. Otherwise
     a later file could override a protected mount.
   - `initializeCommand`: pass the toolchain name to `initialize.sh` (or none).
   - `postStartCommand`: call the toolchain's `post-start.sh` if it has one. Keep the socket cleanup.
   - `customizations.vscode.extensions`: stack-specific extensions.
3. **Keep `remoteEnv` and the VS Code security settings identical to the other variants.**
   devcontainer.json has no include mechanism, so these are duplicated
   (see [security.md](security.md)).
4. Add the variant to the table in `.devcontainer/README.md`.

## Add a toolchain

Create `.devcontainer/shared/toolchains/<name>/`. Every file is optional:

| File | Runs | Notes |
|---|---|---|
| `apt-packages.txt` | build, root | Whitespace-separated packages, `#` comments |
| `install.sh` | build, container user | Create volume mount points here, so fresh volumes are user-owned |
| `init-host.sh <env-file>` | host, before start | Append env vars; `docker volume create` shared volumes. **bash 3.2** |
| `post-start.sh` | container start | Must be idempotent |
| `compose.yml` | — | Must set `build.args.TOOLCHAIN: <name>`; add volumes |

Checklist:
- **Volumes:** per-worktree volumes are named `claude-code-${WORKTREE_NAME:-project}-<what>`.
  Volumes shared across projects are `external: true` and created in `init-host.sh`. Compose
  would otherwise label them with whichever project created them first.
- **Toolchain-specific state:** don't put it in core; core must stay toolchain-agnostic.
- **Only one toolchain per variant:** a later overlay's `TOOLCHAIN` arg would override the
  earlier one. Combining toolchains (e.g. uv + node) needs a combined toolchain folder or a
  change to the Dockerfile.

Notes for planned toolchains:
- **conda:** Miniforge (conda-forge), **not** Anaconda's `defaults` channel (commercial terms).
  Persist `CONDA_ENVS_PATH` and `CONDA_PKGS_DIRS` in volumes.
- **pyenv + poetry:** persist `$PYENV_ROOT/versions`. Set `POETRY_VIRTUALENVS_PATH` to a volume;
  no symlinks are needed.
- **node:** a `node_modules` volume and Playwright browsers (`~/.cache/ms-playwright`). The
  polling env vars in core (`WATCHPACK_POLLING`, `CHOKIDAR_USEPOLLING`) are already there.

## Add an overlay

Put it in `.devcontainer/shared/compose.<feature>.yml` and document it in
`.devcontainer/README.md`. Constraints:
- An overlay must not repeat a mount target that core defines, or it replaces core's mount.
- An overlay must not mount anything at or below a protected path (see [security.md](security.md)).
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
