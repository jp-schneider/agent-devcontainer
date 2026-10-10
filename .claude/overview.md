# Plans overview

## Devcontainer template

### Active
- [`base` variant](plans/2026-10-10-18-28-base-variant.md): generic variant, core image without a toolchain (no Python); quickstart. Implemented, awaiting host verification
- [Protect host-executed paths](plans/2026-10-08-20-30-protect-host-executed-paths.md): read-only mounts for .devcontainer, git hooks/config/modules/worktrees, Claude/VS Code settings; nested-repo scan; container.env
- [Multi-variant devcontainer template](plans/2026-10-08-18-50-multi-variant-devcontainer-template.md): shared hardened core plus per-variant overlays (uv-gpu, uv-cpu); opt-in docker proxy; non-WSL hosts; template-cleanup workflow

### Abandoned
- [Podman overlay](plans/2026-10-10-18-29-podman-overlay.md): rootless Podman inside the devcontainer. Impossible without relaxing Docker's default seccomp (user namespaces need `CAP_SYS_ADMIN`); user requires no extra privileges
