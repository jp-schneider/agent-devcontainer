## Docker Access (Read-Only)
Only applies when the variant includes `compose.docker-proxy.yml`.

Docker access is via a socket proxy that only allows read operations:
- `docker ps` - List running containers
- `docker logs <container>` - View container logs
- `docker inspect <container>` - Inspect container details

**Blocked operations** (for security):
- `docker run` - Cannot create new containers
- `docker exec` - Cannot exec into containers
- `docker build` - Cannot build images

This prevents container escape attacks from malicious code or prompt injection.
