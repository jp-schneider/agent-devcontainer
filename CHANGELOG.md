# Changelog

All notable changes to this template. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/). While the version is 0.x, a minor
release may contain breaking changes; they are listed under **Changed** with migration notes.

Repos created from the template can update with `.devcontainer/update-from-template.sh <tag>`
(see [.devcontainer/README.md](.devcontainer/README.md#updating-from-the-template)).

## [Unreleased]

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
