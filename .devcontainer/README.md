# Devcontainer

This folder sets up a development container for working with a coding agent (Claude Code). The
agent works on your project's code inside the container, but it can't reach the rest of your
machine: not your SSH keys, not your secret files, and not the files your computer runs
automatically later. You keep coding in VS Code as usual; only the environment moves into the
container.

> **Please note:** this is best-effort protection, not a guarantee; read
> [Known limitations](docs/security.md#known-limitations). Review what the agent changed before you run it on your
> own machine. Provided "as is", without warranty. Report security problems privately via
> [Report a vulnerability](https://github.com/jp-schneider/agent-devcontainer/security/advisories/new)
> in the template repository.

| Page | Contents |
|---|---|
| [Getting started](docs/getting-started.md) | requirements, new project or existing repository, check that it works, choosing a variant |
| [Everyday use](docs/everyday-use.md) | rebuilding, `.env` vs. `container.env`, reviewing, pushing |
| [Updating](docs/updating.md) | pulling template updates with `update-from-template.sh`, adopting the template |
| [Customizing](docs/customizing.md) | how-tos: extensions, packages, mounts, services, Node, LaTeX, GPU, local models; best practices |
| [Configuration](docs/configuration.md) | how it is composed: compose files, environment files, overlays, packages, toolchains |
| [Security](docs/security.md) | hardening, protected paths, known limitations |
| [Troubleshooting](docs/troubleshooting.md) | symptoms and fixes |

## What the agent can and can't do

| Inside the container, the agent **can** | It **can't** |
|---|---|
| read and change your project's code | become administrator (no root, no `sudo`) |
| run commands, tests and builds | see secret files: `.env`, private keys, credential files look empty |
| install project dependencies (`uv add`, `npm install`, …) | change files your machine runs later: `.devcontainer/`, git hooks and config, `.vscode/`, Claude settings |
| use the internet | push to your remotes (no SSH keys, no stored passwords) |
| make local git commits | control Docker or other containers on your machine (by default) |

Why these files: anything your machine runs or trusts outside the container (a git hook, the
container setup itself, editor settings) would let the agent run code on your machine. So these
are read-only inside the container, and you edit them from the host. Details:
[Protected paths](docs/security.md#protected-paths).
