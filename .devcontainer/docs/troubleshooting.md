# Troubleshooting

Problems with `update-from-template.sh`: see [updating.md](updating.md#problems).

| Symptom | Cause / fix |
|---|---|
| Start aborts with `protect-paths: ABORT, nested git repositories` | A repo inside the workspace. Remove it, run `git submodule absorbgitdirs`, or allowlist it. |
| `Read-only file system` / `Device or resource busy` | A protected path; edit it on the host. |
| `container name ... is already in use` | An old container from a different setup. On the host: `docker rm -f claude-code-<folder>`. |
| A package or extension is missing after editing | Rebuild, not just reopen. |
| `node post-start: WARNING …/node_modules has no volume` | A package directory added since the last build. Rebuild. |
| `node post-start: WARNING …/node_modules is not writable` | Its volume was created before the image had the mount point. On the host, `docker volume rm` it (name in `.devcontainer/.generated/compose.node.yml`), then rebuild. |
| A file looks empty in the container | It matches a mask pattern (`shared/mask-patterns.txt`). Add an `!` exception in `.devcontainer/mask-patterns.txt` if the agent should see it. |
| What config is actually used? | `.devcontainer/.generated/compose.resolved.yml` (written at each start). |

## The agent says a file is read-only. How do I change it?

That's intended for:
- `.devcontainer/`
- git hooks/config
- `.claude/settings*.json`, `.mcp.json`
- `.vscode/`

Edit those files on the host, then restart or rebuild if needed.
