# Security

Hardening at a glance: no root, all capabilities dropped (`cap_drop: ALL`, `no-new-privileges`), no
SSH/GPG agent, VS Code escape hatches (IPC sockets, credential helpers) cleared, no Docker socket by
default, host-executed paths read-only, secret files masked.

## Protected paths

The agent can't modify files that the host later executes or trusts. These are mounted read-only:
- `.devcontainer/`
- git hooks/config/modules/worktrees, and `commondir` (a read-only placeholder `.`)
- `.claude/settings*.json`, `.mcp.json`
- `.vscode/`

Commits still work; `git config`, `push -u`, `submodule init`, `worktree add` and commits inside
submodules don't (for the last, see the switch below). Placeholders for these paths are created on first start (`.vscode/`,
`.claude/settings*.json`, `.mcp.json`). Commit them or leave them untracked.

**Secret files** are also denied to Claude Code (`.claude/settings.json`, created from
`shared/claude-settings.default.json` if missing; this matters when you run Claude on the host) and
hidden in the container's VS Code Explorer (`files.exclude` in each variant's `devcontainer.json`).
If you add mask patterns, consider adding matching deny rules.

**Nested git repositories:**
- **Known ones are protected like the main repo:** submodules, and directories listed in
  `.devcontainer/allowed-nested-git.txt` (one path per line, relative to the workspace root).
  This includes their `.devcontainer/`, `.vscode/`, `.claude/settings*.json` and `.mcp.json`,
  since you may open them on the host on their own; the rest of their `.claude/` stays writable.
  Missing ones get the same placeholders, so the files show up as untracked in the nested repo
  (commit, ignore or leave them).
- **Unknown ones abort the start,** because host git (and host VS Code, git-aware prompts) would
  run their hooks and config. Remove the repo, run `git submodule absorbgitdirs` for old-style
  submodules, or add the directory to the allowlist on the host.

**Workspace that is itself a submodule** (opened in `A/B`, B a submodule of A): only B's gitdir
`A/.git/modules/B` is mounted, at its host path, not the rest of A. B's `.git` pointer and the
gitdir's `core.worktree` are relative to the host layout, so the container gets generated
replacements (`.devcontainer/.generated/git-links/`): `/app/.git` points to the absolute gitdir,
and its `config` includes the host config, then sets `core.worktree = /app`. Host config changes
stay visible. Submodules of B get the same treatment; one added while the container runs works
after a restart. Superproject commands don't work inside the container.

**Commits inside submodules:** set `DEVCONTAINER_GIT_SUBMODULES_WRITABLE=1` in `.env` on the host.
Checked-out submodules (nested ones too) then get the main repo's protection: their gitdir is
writable, its hooks, config, `modules/`, `worktrees/` and `commondir` stay read-only. A submodule
added while the container runs is writable after the next start; `git submodule add`/`init` still
don't work.

**Developing the template from inside the container:** set `DEVCONTAINER_EDITABLE_BY_AGENT=1` in
`.env` to leave `.devcontainer/` writable. The agent can then change what runs on your host at the
next start, so review `git diff -- .devcontainer` before every restart. Don't use it in
projects.

`.vscode/settings.json` sets `"git.autoRepositoryDetection": false`, so a VS Code opened on the
host doesn't auto-open (and run git in) repos it finds in subfolders. Use "Git: Open Repository"
for nested repos you want to see. The file is read-only inside the container.

Details: `shared/protect-paths.sh`.

## Known limitations

This setup reduces risk; it doesn't remove it. **What this means for you:**
- Review the agent's changes before running anything from the repo on your machine (point 1).
- Treat everything in the workspace and in `container.env` as something the agent could send
  anywhere (point 2).
- Anything you add yourself (extra mounts, Docker access) is outside the protections (point 6).

Known gaps, roughly by importance:

1. **Code you run on the host is not protected.** Anything you deliberately run from this repo
   outside the container may have been written or changed by the agent: `make`, `npm`/`uv run`,
   `pytest`, `pre-commit`, build backends, `.envrc` (direnv asks again after a change), IDE run
   configurations. Review the diff first, or run it in the container.
2. **No egress filtering.** The container has unrestricted outbound network access. Workspace
   contents and `container.env` can be sent anywhere.
3. **Container isolation is the boundary.** The container shares the host kernel, and the
   devcontainer tooling and VS Code have their own attack surface. A kernel or runtime
   vulnerability is outside what this template can address.
4. **Host details are visible.** `/proc/self/mountinfo` shows host paths, your user name and which
   files are masked. This setup protects integrity and secret *files*, not the shape of your
   machine. Don't encode secrets in paths.
5. **Protection is a snapshot taken at start.**
   - Secret files created during a session aren't masked until the next start.
   - A git repo the agent plants during a session is only caught at the next start. Until then,
     host tools that enter it run its config: VS Code opened on the host (not attached), or a
     git-aware shell prompt. `.vscode/settings.json` turns off VS Code's automatic repository
     detection, but that doesn't cover prompts or other IDEs. Avoid host-side git in the
     workspace between an agent session and the next start.
6. **Your additions are outside the protections.**
   - **Extra mounts:** masking and the nested-repo check don't apply to them.
   - **Dev Container Features:** they run as root at build time and can enable `privileged`
     mode, capabilities or mounts.
   - **The Docker proxy overlay:** it exposes all host containers via `docker inspect`.

   See [customizing.md](customizing.md).
7. **Claude deny rules are a second line of defence.** They govern Claude's file tools; a shell
   command like `cat .env` on the host is not reliably covered.
8. **Supply chain.** Base images and the uv/Claude installers are fetched by tag or `curl | sh` at
   build time; only the Docker proxy image is pinned by digest.
9. **Projects are told apart by folder name only.** The compose project, container, Docker
   network (`<folder>-dev`) and the volumes (Claude config, uv venvs, node_modules) are named after
   the workspace folder's name, not its path. Two checkouts with the same folder name (`~/a/app` and
   `~/b/app`, or two submodules both called `app`) share all of them: starting one replaces the
   other's container, they share the Claude config (including the login) and the venvs, and the
   sidecars of one (the unauthenticated LM Studio sidecar, the Docker proxy) are reachable from the
   other. Give every workspace a distinct folder name. Unique names are planned for 0.2.
   Independently, every container can reach ports published on the host, including those of other
   projects' containers.
10. **Details:**
    - Single-file read-only mounts keep showing the old version if the host replaces the file
      (git and Claude write by rename) until the container restarts.
    - The VS Code IPC socket cleanup loop runs for the first 5 minutes; later sockets rely on the
      cleared environment variables.
    - `DEVCONTAINER_EDITABLE_BY_AGENT=1` removes the protection of `.devcontainer/` (template
      development only).

Found another gap, or know how to close one of these? Please contribute; see the
[template repository](https://github.com/jp-schneider/agent-devcontainer).
