# Changelog

All notable changes to this template. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/). While the version is 0.x, a minor
release may contain breaking changes; they are listed under **Changed** with migration notes.

Repos created from the template can update with `.devcontainer/update-from-template.sh <tag>`
(see [.devcontainer/README.md](.devcontainer/README.md#updating-from-the-template)).

## [Unreleased]

### Changed
- **Template repo only: `prepare.sh` commits the release.** It refuses a dirty working tree
  (untracked files included), then commits `CHANGELOG.md` and `.devcontainer/VERSION` as
  "Release vX.Y.Z"; the separate `git commit` step is gone. `--notes` is unchanged.

## [0.1.2] - 2026-10-24

### Changed
- **Template repo only: releases publish on merge.** A pull request that bumps the version with
  `.github/release/prepare.sh` releases when merged: `release.yml` checks the bump
  (`version-to-release.sh`) and creates the tag and the GitHub release from the CHANGELOG section.
  No manual tag step. Repos created from the template get `release.yml` too (inert there); the
  cleanup lists it with the other template workflows to delete.

## [0.1.1] - 2026-10-22

### Added
- **`.devcontainer/apt-packages.txt` ships** (comments only, format in its header), so the project
  apt list is visible. It is project-owned: template updates leave it alone, `--adopt` adds it.
  Repos created from 0.1.0 don't get it by updating; create it when you need it.

### Changed
- **The cleanup asks you to delete the template's workflow files** (`tests.yml`,
  `template-cleanup.yml`): the workflow isn't allowed to, so its run summary shows the `git rm`
  command, and the quick start lists it. Run by hand, `cleanup.sh` deletes them itself.
  Repos created from 0.1.0 can delete them the same way, plus `.github/workflows/release.yml`;
  none of them runs there.
- **Template repo only:** releases go through a pull request (see CONTRIBUTING.md); the release
  workflow is gone, because it can't push to a `main` that requires pull requests.

## [0.1.0] - 2026-10-21

First public version.

### Added
- **Hardened core:** non-root user, `cap_drop: ALL`, `no-new-privileges`, VS Code IPC and
  credential-helper hardening, no Docker socket by default (read-only proxy as an opt-in overlay).
- **Variants** composed from a shared core and overlays: `base` (no toolchain, a generic
  quickstart), `python-uv-cpu` and `python-uv-gpu`.
- **Toolchains**, pluggable and combinable (`initialize.sh <variant> <toolchain>...`, e.g.
  `uv node`; installed and started in that order):
  - `uv` for Python;
  - `node`: Node via fnm (pinned, checksum-verified; per-project versions from `.nvmrc` /
    `.node-version`), npm, pnpm/yarn via corepack (`packageManager`), one volume per
    `node_modules`. Shipped in no variant; CUSTOMIZING.md shows how to add it.
- **Read-only protection** of host-executed paths (`.devcontainer/`, git hooks/config/modules/worktrees,
  Claude and VS Code settings, `.mcp.json`), and an abort on planted nested git repos.
- **Secret masking** via regex patterns, `container.env` vs. host-only `.env`, Claude Code deny
  rules, and a container-only VS Code `files.exclude`.
- **Local models (LM Studio):** `claude-local` (in every image) runs Claude Code against
  LM Studio's Anthropic-compatible API. Two opt-in overlays: `compose.lmstudio-host.yml` (server on
  the host) and `compose.lmstudio-sidecar.yml` (headless llmster container, pinned and
  checksum-verified, sharing the host's model folder). See CUSTOMIZING.md.
- **Project customization:** `compose.project.yml`, project/variant `apt-packages.txt`,
  `DEVCONTAINER_*` compose variables, `CUSTOMIZING.md`.
- **Host detection** (WSL2 / generic), resolved compose config for inspection.
- **Template lifecycle:**
  - a cleanup workflow for new repos: resets README/CLAUDE.md/`.claude/`, removes template-only
    files, moves the template's `LICENSE` to `.devcontainer/LICENSE` so the root is free for the
    project's own;
  - `update-from-template.sh` for updates (default: the latest release tag; `.gitignore` conflicts
    resolved as ours plus the template's missing lines);
  - `update-from-template.sh --adopt` for repos not created from the template: moves the previous
    devcontainer config to `.devcontainer.legacy/`, seeds missing files, lists tracked files that
    are now ignored.
- **CLAUDE.md snippets** in `.devcontainer/claude-md/` to copy as needed: research projects
  (scientific rigor, reproducible runs, plots) and personal preferences in a gitignored
  `CLAUDE.local.md`. The generic `CLAUDE.md` points to them.
- **`.claude/` private by default:** agent plans, memory and scratchpad go to the gitignored
  `.claude/private/`; entries are published by moving them out of it (see `CLAUDE.md`).
- **`.gitignore`** for Python venvs (`.venv`, the uv toolchain's `.venv-<worktree>.ct` links) and
  `node_modules/`.
- **Docker resource names** use the prefix `agent-sandbox-`; `claude-code-*` resources from
  pre-release setups keep working.
- **Template development (template repo only):** bats-core suites in `tests/` with `tests/run.sh`
  (pinned bats), CI on Ubuntu (plus shellcheck) and macOS with bash 3.2, the `template-dev`
  variant, VS Code test tasks (`.vscode/tasks.json`), and a release workflow (Actions → Release:
  tests, `VERSION`, changelog, tag, GitHub release).
