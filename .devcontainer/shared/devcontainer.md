You are running inside a Docker DevContainer.

## Network - IMPORTANT
Use container hostnames, NOT localhost:
- The app container is named after the worktree directory (e.g., `platform-feature-branch`)

## Docker Access
None by default: the Docker socket is not mounted. If the variant enables the
`compose.docker-proxy.yml` overlay, read-only access is available, see
`devcontainer.docker-proxy.md`.

## Read-only paths (by design)
These are mounted read-only because the host executes or trusts them. Writes fail with
"Read-only file system" or "Device or resource busy". Don't try to work around this; ask the
user to make the change on the host.
- `.devcontainer/` (container setup), unless the user enabled template development mode
- `.git/hooks`, `.git/config`, `.git/modules`, `.git/worktrees`. Commits work; `git config`,
  `git push -u`, setting upstreams, `git submodule init` and `git worktree add` don't. Committing
  inside submodules doesn't either.
- `.claude/settings.json`, `.claude/settings.local.json`, `.mcp.json`, `.vscode/`
- Don't create git repositories inside `/app` (`git init`, `git clone`): the next container start
  aborts on them. Clone into `/tmp` instead. Submodules and repos the user allowlisted are fine.
- Secret files (`.env*`, `*.env`, private keys, credential files; see `.devcontainer/shared/mask-patterns.txt`)
  are host-only and appear empty here. Container variables come from `container.env`.

## Git Access (Read + Local Commit Only)
- `git log`, `git status`, `git diff` - Full read access to history
- `git commit`, `git branch` - Can make local commits and branches
- `git push` - **BLOCKED** (no SSH keys mounted)

This prevents malicious code from pushing to remote repositories.

## File System
- Project is at `/app` (same as app container)

## Privilege Restrictions
- No sudo access - cannot escalate privileges
- Non-root user (vscode) with limited capabilities