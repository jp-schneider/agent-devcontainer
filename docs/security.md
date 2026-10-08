# Security model

**Goal:** an agent running inside the container, possibly steered by prompt injection or
malicious dependencies, should not be able to act on the host or on remote accounts beyond the
workspace it was given.

## Layers

| Threat | Mitigation | Where |
|---|---|---|
| Privilege escalation in the container | non-root user, no sudo, `cap_drop: ALL`, `no-new-privileges` | Dockerfile, `compose.core.yml` |
| Container escape via the Docker API | no Docker socket; optional proxy blocks `run`/`exec`/`build`/`commit` | `compose.docker-proxy.yml` |
| Running commands on the host through VS Code IPC | `VSCODE_IPC_HOOK_CLI`, `REMOTE_CONTAINERS_*` unset; IPC sockets deleted | `remoteEnv`, `security-harden.sh`, `command` loop, `postStartCommand` |
| Using host Git credentials / pushing | `GIT_ASKPASS`/`VSCODE_GIT_*` unset; `dockerCredentialHelper` and `copyGitConfig` off; no SSH keys mounted, `SSH_AUTH_SOCK` emptied | `remoteEnv`, `security-harden.sh`, VS Code settings |
| GPG agent, browser, Wayland | `GPG_AGENT_INFO`, `BROWSER`, `WAYLAND_DISPLAY` cleared | same |

**Why the hardening exists in three places:**
- VS Code re-injects some variables after `remoteEnv` is applied. So
  `~/.config/security-harden.sh`, sourced as the first line of `.bashrc` (before the
  interactive guard, so non-interactive shells such as Claude Code's get it too), is the real
  safeguard.
- The socket cleanup runs in the compose `command` loop rather than `postAttachCommand`, because
  VS Code's lifecycle cleanup kills background processes started from the latter.

**Docker proxy trade-off.** Even read-only access with `CONTAINERS=1` lets the agent
`docker inspect` every container on the host, including environment variables and therefore any
secrets passed that way. It is therefore opt-in per variant. The image is pinned by digest.

## Known limitations

These are **not** covered by the current setup. Each is a candidate for follow-up work.

1. **Host-executed files are writable from the container.** The workspace (`/app`) and the main
   repo's `.git` are bind-mounted read-write. An agent can modify:
   - `.devcontainer/shared/initialize.sh` and the scripts it calls, which **run on the host** at
     the next container start;
   - `.git/hooks/*` and `.git/config` (e.g. `core.hooksPath`, `core.fsmonitor`), which **run on
     the host** the next time you use git there;
   - `.vscode/` tasks and settings, which run in the host VS Code (not present in this template).

   Review changes to these paths before restarting the container or running git on the host.
2. **No egress restriction.** The container has unrestricted outbound network access, so data in
   the workspace (and in `.env`, see below) can be exfiltrated.
3. **`.env` files reach the container.** The root `.env` is passed as `env_file` and is visible
   in `/app`. Don't put secrets there that the agent shouldn't have.
4. **The IPC socket cleanup is time-bounded.** The `command` loop runs 10 × 30 s. Sockets that VS
   Code creates later rely on `security-harden.sh` having cleared the variables that point to them.
5. **Image supply chain.** The base images and the uv/Claude installers are fetched at build time
   (tags, `curl | sh`). Only the proxy image is pinned by digest.

## Maintaining

Treat changes to `remoteEnv`, `security-harden.sh`, `compose.core.yml` and the socket cleanup as
security-relevant. They are duplicated in every variant's `devcontainer.json` (`remoteEnv`), so
keep all variants in sync.
