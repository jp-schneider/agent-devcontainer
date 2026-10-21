# Security policy

Thank you for helping make this template safer. It's maintained by one person without a
professional security background, on a best-effort basis. Reports and reviews from the community
are what make it better.

## Supported versions

Only the latest release receives fixes. The project is pre-1.0: interfaces may change between
minor versions when that's needed to close a gap.

## Reporting a vulnerability

**Please don't open a public issue.** Report privately via
[GitHub's private vulnerability reporting](https://github.com/jp-schneider/agent-devcontainer/security/advisories/new)
(Security tab → "Report a vulnerability").

Helpful to include:
- **What an agent inside the container can do that it shouldn't**, e.g. reach the host, modify a
  protected path, read a masked file, or persist something that runs on the host.
- **Steps to reproduce:** variant, host OS (WSL2 / Linux / macOS), Docker and VS Code versions.
- **A suggested fix,** if you have one. Not required.

**What happens next:** you'll get an answer as soon as I can manage. As a volunteer project there's
no guaranteed response time. I'll work with you on a fix and on when to publish, and credit you in
the advisory and changelog unless you prefer otherwise.

## Scope

**In scope:** weaknesses in this template's own configuration and scripts, for example:
- a way around the read-only protections, secret masking or the nested-repo check;
- a container → host escape that the template's settings make possible or fail to prevent;
- secrets or credentials reaching the container through the template's defaults;
- flaws in the scripts that run on the host (`initialize.sh` and friends) or in the GitHub workflow.

**Out of scope here; please report to the respective project:**
- vulnerabilities in Docker / container runtimes, the Linux kernel, VS Code / Dev Containers, or
  Claude Code itself.

**Known limitations** are documented in
[.devcontainer/README.md](.devcontainer/README.md#known-limitations). New attack paths around them,
or ideas to close them, are very welcome, as an issue or pull request if they're not sensitive.
