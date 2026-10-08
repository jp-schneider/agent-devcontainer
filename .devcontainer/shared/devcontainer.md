You are running inside a Docker DevContainer.

## Network - IMPORTANT
Use container hostnames, NOT localhost:
- The app container is named after the worktree directory (e.g., `platform-feature-branch`)

## Docker Access (Read-Only)
Docker access is via a socket proxy that only allows read operations:
- `docker ps` - List running containers
- `docker logs <container>` - View container logs
- `docker inspect <container>` - Inspect container details

**Blocked operations** (for security):
- `docker run` - Cannot create new containers
- `docker exec` - Cannot exec into containers
- `docker build` - Cannot build images

This prevents container escape attacks from malicious code or prompt injection.

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