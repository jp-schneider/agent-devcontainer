# Getting started

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

Pick your path: **A** if you're starting a new repository, **B** if you already have one.

## A. New project

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

## B. Existing repository

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
   (packages, mounts, services; see [customizing.md](customizing.md)), then delete that folder.
8. Commit.
9. Open the folder in VS Code, run **"Dev Containers: Reopen in Container"**, pick a
   [variant](#choosing-a-variant), and run `claude` in the terminal.

What `--adopt` changes in detail: [updating.md](updating.md#what-adopting-changes).

## Check that it works

In a terminal inside the container:

| Command | Expected |
|---|---|
| `whoami` | `vscode` (not `root`) |
| `ls -l .env` | starts with `crw-rw-rw- 1 root root 1, 3`: the file is replaced by an empty device; your real `.env` on the host is unchanged |
| `touch .git/hooks/test` | `Read-only file system` |

If the container doesn't start, see [Troubleshooting](troubleshooting.md).

## Choosing a variant

Each folder with a `devcontainer.json` is one variant. VS Code (and the devcontainer CLI) asks
which one to use when you reopen in the container.

| Variant | Use it for | GPU |
|---|---|---|
| `python-uv-gpu` | Python with CUDA (`nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04`), uv, ruff, ty | yes |
| `python-uv-cpu` | Python without GPU (`ubuntu:24.04`), uv, ruff, ty | no |
| `latex` | LaTeX documents: TeX Live 2023 (curated set), latexmk, biber, LaTeX Workshop (build on save, PDF tab, SyncTeX) | no |
| `base` | anything else; core tools only (git, curl, jq, ripgrep, vim, nano, …). Add packages or a [toolchain](configuration.md#toolchains) | no |

All variants of a worktree share one container name, so switching variants replaces the container.
Node and LaTeX can be added to any variant ([Node](customizing.md#how-do-i-use-node-npm-pnpm),
[LaTeX](customizing.md#how-do-i-write-latex)).
The template repository also has a `template-dev` variant for developing the template itself; it is
removed from new projects.
