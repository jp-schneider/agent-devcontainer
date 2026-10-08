# devcontainer

GitHub template for hardened devcontainers in which coding agents (Claude Code) can run safely.
It has a shared hardened core plus per-stack variants (currently `python-uv-gpu` and
`python-uv-cpu`), and works on WSL2, native Linux and macOS.

- **Using it:** click "Use this template". A workflow then resets this README, `CLAUDE.md` and
  `.claude/` in the new repo and removes `docs/`.
- **Template docs:** architecture, security model, lifecycle, extending and testing are in
  [docs/](docs/README.md) (template only).
- **Details:** variants, overlays, hosts, toolchains and updating are described in
  [.devcontainer/README.md](.devcontainer/README.md).

Files only relevant to developing this template: `CLAUDE.md`, `.claude/` (plans, scratchpad), `docs/`,
`.github/template-cleanup/`.
