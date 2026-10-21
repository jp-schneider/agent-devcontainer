# devcontainer: a hardened home for coding agents

GitHub template for hardened devcontainers in which coding agents, currently claude code can run more safely.
It has a shared hardened core plus per-stack variants (currently `python-uv-gpu` and
`python-uv-cpu`), and works on WSL2, native Linux and macOS.

- **Limited rights:** the agent runs without root, without capabilities and without access to
  your SSH keys or Docker.
- **Integrity of host-executed files:** it can't change files your host executes later (container
  setup, git hooks, editor and Claude settings).
- **Secret files stay hidden:** they look empty inside the container.

It started as a tool for my own research projects. I'm sharing it because I think many people run
agents with more access than they intend, and because it will get better with more eyes on it.

## Features at a glance

- **Hardened container:** non-root user, `cap_drop: ALL`, `no-new-privileges`, no Docker socket by
  default, VS Code escape hatches (IPC sockets, credential helpers) cleared.
- **Host-executed files are read-only** for the agent: `.devcontainer/`, git hooks/config,
  `.claude/` settings, `.mcp.json`, `.vscode/`.
- **Planted nested git repos** abort the container start, because host git would run their hooks.
- **Secret files are masked:** `.env`, keys, credential files and more, via configurable regex
  patterns. Container variables go in a separate `container.env`.
- **Variants:** `python-uv-gpu` (CUDA), `python-uv-cpu` and `base` (no toolchain), built from a
  shared core plus overlays, with pluggable, combinable toolchains (uv; node with fnm, npm, pnpm).
- **Project customization** without touching template files: extra packages, mounts, services.
  Template updates can be merged later.

## Quick start

1. Click **"Use this template"** on GitHub. A workflow then resets this README, `CLAUDE.md` and
   `.claude/` in your new repo and removes `docs/`.
2. Clone it and open it in VS Code with the
   [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
   extension, then choose **"Reopen in Container"** and pick a variant.
3. Read [.devcontainer/README.md](.devcontainer/README.md) (how it works) and
   [.devcontainer/CUSTOMIZING.md](.devcontainer/CUSTOMIZING.md) (extensions, packages, mounts, FAQ).

**Requirements:**
- Docker with Compose v2.
- VS Code with the Dev Containers extension.
- For GPU variants: the NVIDIA container toolkit.

**Tested on:** WSL2. Native Linux and macOS are supported by design but **not tested yet**;
reports are very welcome.

## Please read: security status

I don't have a strong background in IT security. This template is my best effort to apply what I
could learn and reason through. I've documented the design and tested it as well as I can, but
**it hasn't been reviewed by security professionals**, and there are certainly gaps I haven't
thought of.

- **Not a sandbox guarantee.** It reduces the blast radius of a misbehaving or manipulated agent.
- **Known gaps, for example:**
  - no egress filtering;
  - no protection for code *you* run on the host afterwards;
  - the container shares the host kernel.

  The full list: [Known limitations](.devcontainer/README.md#known-limitations).
- **Review what the agent changed** before running anything on your host. Don't give it access to
  anything you couldn't afford to lose.
- **As is:** the software comes without warranty of any kind.

## Contributing: help especially welcome on security

This is meant to be an ongoing community effort, and **contributions are highly appreciated**,
whatever your experience level. Especially valuable:

- **Security review:** threat-model gaps, escape paths I missed, flawed assumptions in
  [docs/security.md](docs/security.md). Even "I'm not sure this is safe because…" is useful.
- **Closing known limitations:** egress filtering, pinning the supply chain, and anything else from
  the [list](.devcontainer/README.md#known-limitations).
- **Testing on other hosts:** native Linux, macOS, other GPUs.
- **New variants and toolchains:** conda, pyenv + poetry, Playwright, … (see
  [docs/extending.md](docs/extending.md)).
- **Docs and usability:** anything that was confusing to set up.

Open an issue to discuss an idea, or send a pull request. [CONTRIBUTING.md](CONTRIBUTING.md) explains
the setup, the tests and the invariants to keep.

**Found a vulnerability?** Please report it **privately** via GitHub's
[Report a vulnerability](https://github.com/jp-schneider/devcontainer/security/advisories/new)
(Security tab) instead of opening a public issue, so it can be fixed before it's widely known.
Details: [SECURITY.md](SECURITY.md).

## Versions

- **Releases** are tagged `vX.Y.Z`; see [CHANGELOG.md](CHANGELOG.md) and the GitHub releases.
- **Pre-1.0:** the project is pre-1.0, so a minor release may contain breaking changes, with
  migration notes.
- **Updating your repo:** run `.devcontainer/update-from-template.sh` in a repo created from the
  template to update it to the latest release.

## Documentation

| Where | What |
|---|---|
| [.devcontainer/README.md](.devcontainer/README.md) | How the container is composed, protected paths, env files, known limitations (kept in your repo) |
| [.devcontainer/CUSTOMIZING.md](.devcontainer/CUSTOMIZING.md) | FAQ and best practices: extensions, packages, software, mounts, services (kept in your repo) |
| [docs/](docs/README.md) | Architecture, security model, template lifecycle, extending, testing (template repo only) |

Files only relevant to developing this template: `CLAUDE.md`, `.claude/` (plans, scratchpad),
`docs/`, `.github/template-cleanup/`.

## License

[MIT](LICENSE)

---

*Independent project, not affiliated with or endorsed by Anthropic. "Claude" is a trademark of
Anthropic.*
