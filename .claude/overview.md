# Plans overview

## Devcontainer template

### Active
- [Local models via LM Studio](plans/2026-10-19-13-07-lmstudio-fallback.md): opt-in overlays (host llmster default, sidecar container), `claude-local` wrapper pointing Claude Code at LM Studio's Anthropic-compatible API
- [Adopt the template in an existing repo](plans/2026-10-10-19-36-adopt-template-in-existing-repo.md): `update-from-template.sh --adopt`; moves an old `.devcontainer/` to `.devcontainer.legacy/`, seeds missing files, `.gitignore` union
- [Tests in the repo (bats) + CI](plans/2026-10-10-19-09-bats-tests-and-ci.md): bats-core suites in tests/, pinned dev dependency, GitHub Actions (Ubuntu + macOS bash 3.2), shellcheck
- [`base` variant](plans/2026-10-10-18-28-base-variant.md): generic variant, core image without a toolchain (no Python); quickstart. Implemented, awaiting host verification
- [Protect host-executed paths](plans/2026-10-08-20-30-protect-host-executed-paths.md): read-only mounts for .devcontainer, git hooks/config/modules/worktrees, Claude/VS Code settings; nested-repo scan; container.env
- [Multi-variant devcontainer template](plans/2026-10-08-18-50-multi-variant-devcontainer-template.md): shared hardened core plus per-variant overlays (uv-gpu, uv-cpu); opt-in docker proxy; non-WSL hosts; template-cleanup workflow

### Done
- [Ignore uv venv links](plans/2026-10-20-12-38-gitignore-uv-venvs.md): `.venv` and `.venv-*.ct` (symlinks, so no trailing slash) in `.gitignore`; `tests/gitignore.bats`

### Abandoned
- [Podman overlay](plans/2026-10-10-18-29-podman-overlay.md): rootless Podman inside the devcontainer. Impossible without relaxing Docker's default seccomp (user namespaces need `CAP_SYS_ADMIN`); user requires no extra privileges
