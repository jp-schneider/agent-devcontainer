# Changelog

All notable changes to this template. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/). While the version is 0.x, a minor
release may contain breaking changes; they are listed under **Changed** with migration notes.

Repos created from the template can update with `.devcontainer/update-from-template.sh <tag>`
(see [.devcontainer/README.md](.devcontainer/README.md#updating-from-the-template)).

## [Unreleased]

### Added
- **`.gitignore` ignores Python venvs:** a plain `.venv` and the uv toolchain's
  `.venv-<worktree>.ct` links, at any depth (`tests/gitignore.bats`).
- **Automated tests:** bats-core suites in `tests/` (protect-paths, initialize, resolve-config,
  host-override, variant invariants, template lifecycle), with `tests/run.sh` (bats pinned as a
  dev dependency). CI runs them on Ubuntu (plus shellcheck) and on macOS with bash 3.2.
- **Variant `base`:** the core image without a toolchain (no Python), as a generic quickstart.
- **Adopting the template in an existing repo:** `update-from-template.sh --adopt` merges the
  template into a repo not created from it. It moves the previous devcontainer config to
  `.devcontainer.legacy/`, adds missing files (`compose.project.yml`, `.claude/settings.json`, generic
  `CLAUDE.md` and `.claude/` skeleton) and lists tracked files that are now ignored.
- **Local models (LM Studio):** `claude-local` (in every image) runs Claude Code against
  LM Studio's Anthropic-compatible API. There are two opt-in overlays: `compose.lmstudio-host.yml` (server on
  the host) and `compose.lmstudio-sidecar.yml` (headless llmster container, pinned and
  checksum-verified, sharing the host's model folder). See CUSTOMIZING.md.

### Changed
- `host-override.sh`: new test hook `WSL_LIB_DIR`; behaviour unchanged.
- The cleanup and `update-from-template.sh` treat `tests/` and the tests workflow as template-only.
- `update-from-template.sh`: a `.gitignore` conflict is resolved as ours plus the template's
  missing lines; stops if `git merge` didn't start; never merges in the template-cleanup workflow.

## [0.1.0] - unreleased

First public version.

### Added
- **Hardened core:** non-root user, `cap_drop: ALL`, `no-new-privileges`, VS Code IPC and
  credential-helper hardening, no Docker socket by default (read-only proxy as an opt-in overlay).
- **Variants** `python-uv-gpu` and `python-uv-cpu`, composed from a shared core and overlays, with
  pluggable toolchains (`uv`).
- **Read-only protection** of host-executed paths (`.devcontainer/`, git hooks/config/modules/worktrees,
  Claude and VS Code settings, `.mcp.json`), and an abort on planted nested git repos.
- **Secret masking** via regex patterns, `container.env` vs. host-only `.env`, Claude Code deny
  rules, and a container-only VS Code `files.exclude`.
- **Project customization:** `compose.project.yml`, project/variant `apt-packages.txt`,
  `DEVCONTAINER_*` compose variables, `CUSTOMIZING.md`.
- **Host detection** (WSL2 / generic), resolved compose config for inspection.
- **Template lifecycle:** cleanup workflow for new repos, `update-from-template.sh` for updates.
