# Template documentation

Documentation for **maintaining and understanding this devcontainer template**. This folder is
removed from repos created with "Use this template" (see [lifecycle.md](lifecycle.md)). The
user-facing guide that stays in every derived repo is [.devcontainer/README.md](../.devcontainer/README.md).

| Page | Contents |
|---|---|
| [architecture.md](architecture.md) | How a variant is assembled: compose overlays, Dockerfile build args, generated files, start-up sequence |
| [security.md](security.md) | What the container protects against, how, and what it does **not** protect against |
| [lifecycle.md](lifecycle.md) | "Use this template" → cleanup workflow → pulling template updates |
| [extending.md](extending.md) | Adding a variant, a toolchain, an overlay; overriding the base image |
| [testing.md](testing.md) | How changes to the template are verified, offline and on hosts |

## Repository layout

```
.devcontainer/
├── README.md                    user guide (kept in derived repos)
├── CUSTOMIZING.md               FAQ + best practices for template users (kept in derived repos)
├── update-from-template.sh      merge template updates into a derived repo (default: latest release tag)
├── VERSION                      template version of this checkout (kept in derived repos)
├── python-uv-gpu/devcontainer.json
├── python-uv-cpu/devcontainer.json
├── .generated/                  gitignored, written by initialize.sh (host, protect, resolved)
├── allowed-nested-git.txt       optional: nested repos to allow (and protect)
├── mask-patterns.txt            optional: project mask additions/exceptions
├── compose.project.yml          project compose file: mounts, services, resources (project-owned)
├── apt-packages.txt             optional: project apt packages (all variants)
├── <variant>/apt-packages.txt   variant apt packages (Python variants: OpenCV runtime by default)
├── .dockerignore                build context = .devcontainer/; only Dockerfile, toolchains, apt list
└── shared/
    ├── Dockerfile               one image definition for all variants
    ├── compose.core.yml         hardened core, always first
    ├── compose.gpu.yml          overlay: NVIDIA GPU + CUDA base image
    ├── compose.docker-proxy.yml overlay (opt-in): read-only Docker API
    ├── initialize.sh            host-side, before every start
    ├── host-override.sh         host detection → .generated/compose.host.yml
    ├── protect-paths.sh         read-only binds + secret masks → .generated/compose.protect.yml
    ├── mask-patterns.txt        regexes of files hidden from the container
    ├── claude-settings.default.json  default .claude/settings.json: deny rules for secret files
    ├── resolve-config.sh        docker compose config → .generated/compose.resolved.yml
    ├── devcontainer.md          agent-facing environment notes (imported by CLAUDE.md)
    ├── devcontainer.docker-proxy.md
    └── toolchains/uv/           apt-packages.txt, install.sh, init-host.sh, post-start.sh, compose.yml
.github/
├── workflows/template-cleanup.yml
└── template-cleanup/            cleanup.sh + files/ (generic CLAUDE.md, skeletons, jokes)
docs/                            this folder (template only)
SECURITY.md, CONTRIBUTING.md, CHANGELOG.md   template only (removed by cleanup, never merged into derived repos)
CLAUDE.md, .claude/              template development history (template only)
```

## Design decisions in one place

| Decision | Why |
|---|---|
| One repo, shared core + overlays (not one repo per stack) | Security fixes land once; variants stay ~30 lines each |
| Overlays via compose file lists, not a single parametrized config | Each file is reviewable on its own; no conditionals in YAML |
| Variants as `.devcontainer/<name>/` folders | Native devcontainer multi-config; VS Code offers a picker |
| GitHub template + git-merge updates (no Copier) | No extra tooling; files stay plain YAML/bash, not Jinja |
| Docker proxy opt-in | `docker inspect` leaks env vars of every container on the host |
| Claude Code installed at build time | Pinned per image; no unpinned `curl \| bash` on every start |
| Cleanup runs once; updates via a script | A re-run would overwrite the derived repo's own CLAUDE.md/README |

The full history of these decisions is in `.claude/plans/` (template repo only).
