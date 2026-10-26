# Devcontainer

This folder sets up a development container for working with a coding agent (Claude Code). The
agent works on your project's code inside the container, but it can't reach the rest of your
machine: not your SSH keys, not your secret files, and not the files your computer runs
automatically later. You keep coding in VS Code as usual; only the environment moves into the
container.

> **Please note:** this is best-effort protection, not a guarantee; read
> [Known limitations](#known-limitations). Review what the agent changed before you run it on your
> own machine. Provided "as is", without warranty. Report security problems privately via
> [Report a vulnerability](https://github.com/jp-schneider/agent-devcontainer/security/advisories/new)
> in the template repository.

- [What the agent can and can't do](#what-the-agent-can-and-cant-do)
- [Before you start](#before-you-start)
- [Getting started](#getting-started): [A. New project](#a-new-project) ·
  [B. Existing repository](#b-existing-repository) · [Check that it works](#check-that-it-works)
- [Choosing a variant](#choosing-a-variant)
- [Everyday use](#everyday-use)
- [Updating from the template](#updating-from-the-template)
- [Known limitations](#known-limitations)
- More: [CUSTOMIZING.md](CUSTOMIZING.md) (how-tos, troubleshooting) ·
  [REFERENCE.md](REFERENCE.md) (how it works)

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
[REFERENCE.md](REFERENCE.md#protected-paths).

## Before you start

You need:
- **Docker** with Compose v2 (Docker Desktop includes both).
- **VS Code** with the
  [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
  extension.
- For the GPU variant: an NVIDIA GPU and, on native Linux, the NVIDIA container toolkit.

| Your machine | Notes |
|---|---|
| Windows (WSL2) | Tested. GPU driver libraries (`/usr/lib/wsl`) are mounted automatically. |
| Native Linux | Supported, not tested yet. GPU variant needs the NVIDIA container toolkit. |
| macOS | Supported, not tested yet. CPU variants only. |

Reports from untested hosts are very welcome.

## Getting started

Pick your path: **A** if you're starting a new repository, **B** if you already have one.

### A. New project

1. On the [template's GitHub page](https://github.com/jp-schneider/agent-devcontainer), click **"Use this
   template"** and create your repository.
2. Wait a minute or two, then refresh the page. A workflow
   (`.github/workflows/template-cleanup.yml`) replaces the template's `README.md`,
   `CLAUDE.md` and `.claude/` with fresh files for your project and removes template-only files.
   - If it didn't run, or couldn't push (Settings → Actions → General → Workflow permissions must
     allow "Read and write"), run it yourself after cloning, then commit. Only if the folder
     `.github/template-cleanup/` still exists:
     ```bash
     bash .github/template-cleanup/cleanup.sh
     ```
     Run by hand, it also removes the template's workflow files (step 4).
3. Clone the repository and open the folder in VS Code.
4. Delete the template's workflow files. The workflow isn't allowed to (they never run in your
   repo; its run summary shows the same command):
   ```bash
   git rm .github/workflows/tests.yml .github/workflows/release.yml .github/workflows/template-cleanup.yml
   git commit -m "Remove template workflows" && git push
   ```
5. Run **"Dev Containers: Reopen in Container"** (command palette, `F1`) and pick a
   [variant](#choosing-a-variant). The first build takes several minutes.
6. Optional: delete the variant folders you don't need (on the host), so VS Code stops asking.
7. Open a terminal in VS Code and run `claude`.

Continue with [Check that it works](#check-that-it-works).

### B. Existing repository

This adds the template to a repository that wasn't created from it. Your old devcontainer setup,
if any, is moved aside, not deleted.

1. On your machine (not inside a container), go to the repository root. Commit or stash your
   changes first; the script needs a clean working tree (changes inside submodules are fine) and
   at least one commit.
2. Fetch the template and extract the setup script:
   ```bash
   git remote add template https://github.com/jp-schneider/agent-devcontainer.git
   git fetch template
   git show template/main:.devcontainer/update-from-template.sh > /tmp/update-from-template.sh
   ```
3. **Read the script before running it** (`less /tmp/update-from-template.sh`). It's code from the
   internet that will change your repository.
4. Run it:
   ```bash
   bash /tmp/update-from-template.sh --adopt          # latest release; or: --adopt v0.2.0
   ```
   It merges the template but doesn't commit, so you can review everything first.
5. Resolve conflicts (`git status` lists them). `.vscode/settings.json` usually conflicts: keep
   your settings and add `"git.autoRepositoryDetection": false`.
6. The script lists tracked files that are now ignored (e.g. a committed `*.env`). Check them for
   secrets, then untrack them with `git rm --cached <file>`.
7. If you had a devcontainer before, it's now in `.devcontainer.legacy/`. Port what you need
   (packages, mounts, services; see [CUSTOMIZING.md](CUSTOMIZING.md)), then delete that folder.
8. Commit.
9. Open the folder in VS Code, run **"Dev Containers: Reopen in Container"**, pick a
   [variant](#choosing-a-variant), and run `claude` in the terminal.

<details>
<summary>What <code>--adopt</code> changes in detail</summary>

On top of a normal [update](#updating-from-the-template), `--adopt`:
- **moves your previous devcontainer config** (everything tracked under `.devcontainer/`, and a root
  `.devcontainer.json`) to `.devcontainer.legacy/`. VS Code doesn't look there;
- **adds missing files** from the template, never overwriting yours: `.devcontainer/compose.project.yml`
  (every variant needs it), `.devcontainer/apt-packages.txt` (empty), `.claude/settings.json` (deny rules), and a generic `CLAUDE.md`,
  `.claude/overview.md`, `.claude/memory/MEMORY.md`. Files your `.gitignore` ignores are skipped;
- **lists tracked files that are now ignored**;
- refuses to run if the repo already has the template (`.devcontainer/VERSION`) or
  `.devcontainer.legacy/` exists.

Your own `README.md` and `.claude/` are kept, as on updates.

This is a real merge, so the template's commits become part of your history (`git log --first-parent`
hides them). In return, later updates have a common ancestor and merge normally, with the plain
`bash .devcontainer/update-from-template.sh`.
</details>

### Check that it works

In a terminal inside the container:

| Command | Expected |
|---|---|
| `whoami` | `vscode` (not `root`) |
| `ls -l .env` | starts with `crw-rw-rw- 1 root root 1, 3`: the file is replaced by an empty device; your real `.env` on the host is unchanged |
| `touch .git/hooks/test` | `Read-only file system` |

If the container doesn't start, see [Troubleshooting](CUSTOMIZING.md#troubleshooting).

## Choosing a variant

Each folder with a `devcontainer.json` is one variant. VS Code (and the devcontainer CLI) asks
which one to use when you reopen in the container.

| Variant | Use it for | GPU |
|---|---|---|
| `python-uv-gpu` | Python with CUDA (`nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04`), uv, ruff, ty | yes |
| `python-uv-cpu` | Python without GPU (`ubuntu:24.04`), uv, ruff, ty | no |
| `base` | anything else; core tools only (git, curl, jq, ripgrep, vim, nano, …). Add packages or a [toolchain](REFERENCE.md#toolchains) | no |

All variants of a worktree share one container name, so switching variants replaces the container.
Node can be added to any variant ([CUSTOMIZING.md](CUSTOMIZING.md#how-do-i-use-node-npm-pnpm)).
The template repository also has a `template-dev` variant for developing the template itself; it is
removed from new projects.

## Everyday use

- **Change the container setup on the host, then rebuild.** `.devcontainer/` is read-only inside
  the container, so the agent can't change what runs on your machine. After editing, run
  **"Dev Containers: Rebuild Container"**; a plain reopen doesn't pick up changes.
- **Keep secrets in `.env`, not `container.env`.** Both live in the repo root, are gitignored and
  are created empty on first start.

  | File | The agent sees it? | Put here |
  |---|---|---|
  | `container.env` | **yes**, as environment variables | settings the container needs; only tokens you'd accept the agent reading |
  | `.env` | no (looks empty) | secrets and host-only settings |

  Other secret-looking files (keys, credential files, `secrets.*`) are hidden the same way. To hide
  more, see [REFERENCE.md](REFERENCE.md#environment-files).
- **Review before you run on your machine.** After an agent session, check `git diff` before you run
  anything from the repo outside the container (`make`, `pytest`, `uv run`, `npm`, …). The agent may
  have changed it. Running it inside the container is always fine.
- **Push from the host.** The agent can commit but not push. See
  [How do I commit and push?](CUSTOMIZING.md#how-do-i-commit-and-push)
- **Adding things** (VS Code extensions, system packages, datasets, databases, GPU, permissions
  for Claude): see [CUSTOMIZING.md](CUSTOMIZING.md).

## Updating from the template

Repos created with "Use this template" have no shared git history with the template. Your
template version is in `.devcontainer/VERSION`; releases and their changes are listed at
https://github.com/jp-schneider/agent-devcontainer/releases. To update:

```bash
bash .devcontainer/update-from-template.sh           # latest release (vX.Y.Z tag)
bash .devcontainer/update-from-template.sh v0.2.0    # a specific release (or a branch name)
```

The script prints the version change (e.g. `0.1.0 -> 0.2.0`). `.devcontainer/VERSION` always
takes the template's value.
- **Merge behaviour:** it merges `template/main` without committing, keeps this repo's own
  `CLAUDE.md`, `README.md`, `.claude/` and `docs/`, and drops template-only files. Conflicts on
  those paths are resolved automatically; only the remaining ones are listed at the end.
- **Clean working tree:** commit or stash first. Changes inside submodules (and new submodule
  commits you haven't staged) don't count and stay as they are. Ignored local files at a path where
  the template has a file you don't track would be overwritten by git, so the script stops and
  lists them; move them away and run it again.
- **First run, or after a squash-merged update:** there is no common history with the template,
  so the script uses the template release in `.devcontainer/VERSION` as the merge base. Only files
  you changed since that release conflict. If `VERSION` names no release (e.g. you started from an
  unreleased `main`), every file that differs from the template conflicts. The commit records the
  template as a merge parent, so later updates merge normally; merge the update PR with a merge
  commit, not squash, to keep that link.
- **Deleted variants:** variants you deleted come back if the template changed them. Delete them again.
- **`.gitignore` conflicts** are resolved automatically: your lines, plus the template's missing
  ones under `# devcontainer template`.

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

   See [CUSTOMIZING.md](CUSTOMIZING.md).
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
