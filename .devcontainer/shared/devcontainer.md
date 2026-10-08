You are running inside a Docker DevContainer.

## Network - IMPORTANT
Use container hostnames, NOT localhost:
- The app container is named after the worktree directory (e.g., `platform-feature-branch`)

## Docker Access
None by default: the Docker socket is not mounted. If the variant enables the
`compose.docker-proxy.yml` overlay, read-only access is available, see
`devcontainer.docker-proxy.md`.

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