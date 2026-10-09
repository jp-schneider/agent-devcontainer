# devcontainer

GitHub template for hardened devcontainers in which coding agents, currently claude code can run more safely.
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

## Security disclaimer

This template is a best-effort hardening of a devcontainer for coding agents. It reduces the blast
radius of a misbehaving or manipulated agent: no root, no capabilities, no Docker socket, read-only
host-executed paths, masked secret files. It is **not** a guarantee: container isolation, the
devcontainer tooling and VS Code all have their own attack surface. Some gaps are known and
documented, e.g. no egress filtering and no protection for code you run on the host yourself (see
[docs/security.md](docs/security.md#known-limitations)). Review what the agent changed before you
run it on your host, and don't give it access to anything you couldn't afford to lose. The
software is provided "as is", without warranty of any kind.

Contributions are welcome: issues, pull requests, and ideas for further hardening. Please report
security problems **privately** via GitHub's "Report a vulnerability" (Security tab) rather than
in a public issue.
