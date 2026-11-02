# Everyday use

- **Change the container setup on the host, then rebuild.** `.devcontainer/` is read-only inside
  the container, so the agent can't change what runs on your machine. After editing, run
  **"Dev Containers: Rebuild Container"**; a plain reopen doesn't pick up changes.
- **Keep secrets in `.env`, not `container.env`.** Both live in the repo root, are gitignored and
  are created empty on first start.

  | File | The agent sees it? | Put here |
  |---|---|---|
  | `container.env` | **yes**, as environment variables | settings the container needs; only tokens you'd accept the agent reading |
  | `.env` | no (looks empty) | secrets and host-only settings |

  Other secret-looking files (keys, credential files, `secrets.*`) are hidden the same way. To hide
  more, see [configuration.md](configuration.md#environment-files).
- **Review before you run on your machine.** After an agent session, check `git diff` before you run
  anything from the repo outside the container (`make`, `pytest`, `uv run`, `npm`, …). The agent may
  have changed it. Running it inside the container is always fine.
- **Push from the host.** The agent can commit but not push. See
  [How do I commit and push?](customizing.md#how-do-i-commit-and-push)
- **Adding things** (VS Code extensions, system packages, datasets, databases, GPU, permissions
  for Claude): see [customizing.md](customizing.md).
