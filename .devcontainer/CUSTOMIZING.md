# Customizing the devcontainer

How to adapt the container to your project without weakening its protections. Overview of the
setup: [README.md](README.md).

## Ground rules

- **Make changes on the host.** Everything under `.devcontainer/` is read-only inside the container,
  so the agent can't change what runs on your host. You edit it from the host, then **rebuild**
  (VS Code: "Dev Containers: Rebuild Container"). A plain reopen doesn't pick up image changes.
- **Leave `shared/` alone where you can.** It belongs to the template; local edits there conflict
  when you pull template updates (`update-from-template.sh`). Put project changes in the files
  named below (variant folder, project files). Keep edits to a variant's `devcontainer.json` small.
- **There is no `sudo` in the container.** System-level changes happen at image build, never at
  runtime.

## FAQ

### How do I install a VS Code extension?

While you can install extensions in the container via the Extensions view, they are not saved in the image and don't survive a rebuild. To have them persist across rebuilds, add them to the variant's `devcontainer.json` so they are installed at build time.
Add its ID (the unique identifier mentioned in the extension's details) to the variant's `devcontainer.json` optionally perform a rebuild to test it. For example, to add the "Even Better TOML" extension:

```jsonc
// .devcontainer/<variant>/devcontainer.json
"customizations": {
  "vscode": {
    "extensions": [
      "ms-python.python",
      "tamasfe.even-better-toml"   // new
    ]
  }
}
```

- **Find the ID** in the Extensions view: right-click → "Copy Extension ID".
- **Personal extensions** that only you want (themes, keymaps) belong in your host VS Code user
  setting `dev.containers.defaultExtensions`, not in the repo.
- **Extensions run inside the container with the agent's permissions** and can read the workspace.
  Prefer well-known publishers.

### How do I install system (apt) packages?

List them in an apt package file, then rebuild:

| File | Applies to |
|---|---|
| `.devcontainer/apt-packages.txt` | all variants (create it if you need it) |
| `.devcontainer/<variant>/apt-packages.txt` | one variant (the Python variants ship the OpenCV runtime here) |

```
# whitespace-separated, # comments, optional version pins
libpq-dev
graphviz=2.42.2-9ubuntu0.1
```

- **Pins are passed to apt as-is.** Ubuntu removes old versions from its archive, so a pin can
  break a later rebuild. Pin only when you must.
- **The container can't do this at runtime:** there's no `sudo`.

### How do I install other software (not from apt)?

Pick by what it is:

| What | Where | Persists across rebuilds? |
|---|---|---|
| Language runtime / common tool (Node, Go, Rust, AWS CLI, …) | [Dev Container Feature](https://containers.dev/features) in `devcontainer.json` | yes (in the image) |
| Python CLI tools (pre-commit, nox, …) | your project's dev dependencies (`uv add --dev …`), run via `uv run` | yes (venv volume) |
| User-level tools for everyone in the project | `postCreateCommand` in `devcontainer.json` (e.g. `uv tool install …`) | re-run on each container creation |
| A reusable stack for several projects | a new toolchain in `shared/toolchains/` (template change; see the template's `docs/extending.md`) | yes |

Feature example:

```jsonc
// .devcontainer/<variant>/devcontainer.json
"features": {
  "ghcr.io/devcontainers/features/node:1": { "version": "22" }
}
```

> **Security: check a Feature before adding it.** Features run as root at build time, and their
> metadata can change the container: `privileged`, `capAdd`, `securityOpt`, `mounts`, `init`.
> For example, `docker-in-docker` sets `privileged: true`, which undoes most of this setup. Read
> the Feature's `devcontainer-feature.json` and pin a major version (`:1`).

Tools installed by hand inside a running container (`uv tool install`, `npm -g`, `curl | sh` into
`~/.local`) disappear when the container is recreated. That's on purpose: write the install down
in one of the places above.

### How do I mount other files or folders (datasets, model weights, …)?

Add the mount to **`.devcontainer/compose.project.yml`**. That's your project's compose file:
- every variant already lists it, after the template files and before the generated protection
  overlay;
- template updates leave it alone.

```yaml
# .devcontainer/compose.project.yml
services:
  claude-code:
    volumes:
      - type: bind
        source: ${DEVCONTAINER_DATA_PATH}   # from .env on the host
        target: /data
        read_only: true                     # default to read-only
    environment:
      DATA_PATH: /data                      # optional: your code reads the same name everywhere
```

Define the host path in `.env` (host-only), **with the `DEVCONTAINER_` prefix**:
```
DATA_PATH=/home/me/data                    # for running locally on the host (not used by the devcontainer)
DEVCONTAINER_DATA_PATH=/mnt/storage/data   # for the devcontainer's compose files
```

**Variables:** `DEVCONTAINER_*` lines in `.env` are **compose-time** variables. They are available
as `${DEVCONTAINER_…}` in compose files, for mounts, build args and service settings. They are not
environment variables in the container, and the Dockerfile doesn't see them unless you map one
via `build.args` or `environment:`.
- **The prefix keeps the namespaces apart:** `DATA_PATH` for local runs and
  `DEVCONTAINER_DATA_PATH` for the devcontainer can have different values. The prefix also means
  no variable of yours can collide with compose's own settings (`COMPOSE_PROJECT_NAME`, …) or the
  generated ones.
- **Only prefixed lines reach compose.** Unprefixed `.env` lines (secrets, host settings) never do.
- **Nothing reaches the container unless you reference it:** a mount path (visible via
  `/proc/self/mountinfo`), or a value you put under `environment:`. So don't put secrets in
  `DEVCONTAINER_*` variables you reference.
- **The difference to `container.env`:** that file sets environment variables *inside* the
  container; compose can't use it for mounts or the build.

**What to know about extra mounts:**
- **They are outside the protections.** Secret masking and the nested-repo check only cover the
  workspace, so mounted folders are fully visible to the agent.
- **Read-write mounts give the agent write access** to that data. Use `read_only: true` unless it
  must write (e.g. a runs/output folder).
- **Mount narrowly:** the folder you need, not `$HOME` or `/`.
- **Never mount:**
  - `~/.ssh`, `~/.aws`, `~/.config`, `~/.gitconfig` or other credential stores;
  - `/var/run/docker.sock`;
  - other git repositories with write access (their hooks would run on your host).
- **Prefer targets outside `/app`** (e.g. `/data`, `/runs`). A target inside the workspace is
  fine, but should be gitignored.

### How do I pass environment variables or API keys?

Put them in `container.env` (repo root, gitignored), then rebuild or recreate the container:
```
WANDB_API_KEY=...
HF_HOME=/data/hf-cache
```
- **The agent can read everything in `container.env`.** Give it scoped, short-lived or read-only
  tokens, never your main credentials.
- **Host-only values belong in `.env`.** That file is masked in the container.

### How do I add a database or another service?

Add a service to `.devcontainer/compose.project.yml`:
```yaml
services:
  db:
    image: postgres:16.4          # pin a version
    environment:
      POSTGRES_PASSWORD: dev-only
    networks: [dev]
```
- **Reach it by service name** from the container (`db:5432`), not `localhost`.
- **Use `forwardPorts`** in `devcontainer.json` to open a port in your host browser.

### How do I add Python dependencies?

Use uv as usual (`uv add …`, `uv sync`). Each project's venv lives in a persistent volume and
survives rebuilds; the link is `.venv-<worktree>.ct`, see [README.md](README.md#uv-details). Don't
create `.venv` by hand.

### How do I use the GPU or give the container more resources?

- **GPU:** use a `*-gpu` variant (needs the NVIDIA container toolkit on the host).
- **Limits and shared memory:** set them in `.devcontainer/compose.project.yml`, e.g. for PyTorch data loaders:
```yaml
services:
  claude-code:
    shm_size: "8gb"
    deploy:
      resources:
        limits: { cpus: "8", memory: 32G }
```

### How do I commit and push?

- **The agent can commit locally.** It can't push: no SSH keys, and the credential helpers are
  disabled. Review and push from the host.
- **Commit identity:** set it in `container.env`:
  ```
  GIT_AUTHOR_NAME=...
  GIT_AUTHOR_EMAIL=...
  GIT_COMMITTER_NAME=...
  GIT_COMMITTER_EMAIL=...
  ```
- **Repo git config** (`.git/config`) is read-only in the container. Change remotes and settings
  on the host.

### Claude keeps asking for the same permission. How do I make it stick?

"Always allow" can't be saved from inside the container: `.claude/settings*.json` are read-only.
Add the rule on the host to `.claude/settings.json` (shared with the team) or
`.claude/settings.local.json` (just you):
```json
{ "permissions": { "allow": ["Bash(uv run pytest:*)"] } }
```
Keep the `deny` rules that the template ships.

### The agent says a file is read-only. How do I change it?

That's intended for:
- `.devcontainer/`
- git hooks/config
- `.claude/settings*.json`, `.mcp.json`
- `.vscode/`

Edit those files on the host, then restart or rebuild if needed.

### Can I use submodules or other repositories inside the workspace?

- **Submodules:** yes.
- **Other nested repositories:** the start aborts. If you need one, list its directory in
  `.devcontainer/allowed-nested-git.txt` (one path per line); it is then protected like the main
  repo.
- **Clones the agent makes** belong in `/tmp`.

### How do I use local models (LM Studio)?

LM Studio (≥ 0.4.1) serves an Anthropic-compatible API, so Claude Code itself talks to it. You get
the same tools (Read/Edit/Write/Bash), permissions, CLAUDE.md and container protections; only the
model differs. Uses: working entirely with local models, with no Claude account; keeping code
on your machine; or switching to a local model now and then. `claude-local [args]` sets this up for one
process. Plain `claude` and the VS Code extension keep talking to Anthropic.

**1. Pick where LM Studio runs** and add that overlay to the variant's `dockerComposeFile`, before
`compose.project.yml`. Then rebuild:

```jsonc
"dockerComposeFile": [
  "../shared/compose.core.yml",
  "../shared/toolchains/uv/compose.yml",
  "../shared/compose.lmstudio-host.yml",   // or compose.lmstudio-sidecar.yml, not both
  "../compose.project.yml",
  ...
```

| | `compose.lmstudio-host.yml` (default) | `compose.lmstudio-sidecar.yml` |
|---|---|---|
| Runs | LM Studio app or `llmster` on the host | `llmster` in a container on the dev network |
| Pick models | GUI, or `lms get` / `lms load` on the host | `docker exec lmstudio-<worktree> lms get …` / `lms load …` |
| GPU | the host's, outside Docker | NVIDIA container runtime; competes for VRAM with the dev container |
| Auth | turn on "Require Authentication" | none (no published port) |

**Host mode, server start.** Bind to the Docker bridge, not to all interfaces:
```bash
lms server start --port 1234 --bind "$(ip -4 -o addr show docker0 | awk '{print $4}' | cut -d/ -f1)"
```
`docker0` must exist (Docker running) before the server starts. On Docker Desktop,
`host.docker.internal` points at the Desktop host, so which bind is reachable depends on where LM
Studio runs; check with the `curl` from step 3. A server elsewhere:
`DEVCONTAINER_LMSTUDIO_URL=http://<host>:1234` in the root `.env`.

**Sidecar mode.** The models folder (default `~/.lmstudio/models`, or
`DEVCONTAINER_LMSTUDIO_MODELS_DIR` in `.env`) must exist on the host. Rebuild to update llmster:
version and checksum are pinned in `shared/lmstudio/Dockerfile`. On WSL, if the sidecar doesn't see
the GPU, mount the WSL driver libraries for it in `compose.project.yml`:
```yaml
services:
  lmstudio:
    volumes: ["/usr/lib/wsl:/usr/lib/wsl:ro"]
    environment: {LD_LIBRARY_PATH: /usr/lib/wsl/lib}
```

**2. `container.env`:**
```bash
LMSTUDIO_MODEL=openai/gpt-oss-20b     # the key `lms ls` / /v1/models shows; --model overrides it
LMSTUDIO_API_TOKEN=...                 # host mode with authentication; visible to the agent
```

**3. In the container:** `curl -s $LMSTUDIO_BASE_URL/v1/models` should list the model; then `claude-local`.

**What to expect:**
- **Context:** Claude Code's system prompt plus CLAUDE.md files is large. Load the model with ≥ 64k
  context (`lms load <model> --context-length 65536`); LM Studio's stated minimum is about 25k.
- **Quality:** multi-step edits depend on the model's tool calling. Larger, tool-tuned coding models
  work better.
- **Not verified, likely unavailable:** WebSearch/WebFetch (Anthropic server-side) and claude.ai connectors.
  Without prompt caching every turn re-reads the context, which is slow on long sessions. Images
  need a vision model.
- History and memory live in the same `~/.claude`. Resuming a session that started on Claude may
  fail.

### Which variant should I keep?

- **Delete the variant folders you don't use.** VS Code then stops asking.
- **One container per worktree:** switching variants replaces the container.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Start aborts with `protect-paths: ABORT, nested git repositories` | A repo inside the workspace. Remove it, run `git submodule absorbgitdirs`, or allowlist it. |
| `Read-only file system` / `Device or resource busy` | A protected path; edit it on the host. |
| `container name ... is already in use` | An old container from a different setup. On the host: `docker rm -f claude-code-<folder>`. |
| A package or extension is missing after editing | Rebuild, not just reopen. |
| A file looks empty in the container | It matches a mask pattern (`shared/mask-patterns.txt`). Add an `!` exception in `.devcontainer/mask-patterns.txt` if the agent should see it. |
| What config is actually used? | `.devcontainer/.generated/compose.resolved.yml` (written at each start). |

## Best practices

- **Least privilege first:** no Docker proxy unless needed; read-only mounts; scoped tokens in
  `container.env`.
- **Everything reproducible:** every package, tool and mount is declared in a file and installed at
  build or create time, never by hand in a running container.
- **Pin what you depend on:** Feature major versions, service image tags, apt versions only when
  needed.
- **Review before running on the host:** `git diff` after an agent session, especially build files,
  scripts, CI config and anything you'll run outside the container.
- **Keep template files untouched** where possible. Project changes belong in the project files:
  `compose.project.yml`, `apt-packages.txt`, `mask-patterns.txt`, `allowed-nested-git.txt`, and
  the variant's `apt-packages.txt`. Template updates then merge cleanly.
- **New secret file types:** add a regex to `.devcontainer/mask-patterns.txt` and a matching
  `Read(...)` deny rule to `.claude/settings.json`.
