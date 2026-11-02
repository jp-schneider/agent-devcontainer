# Updating from the template

Your template version is in `.devcontainer/VERSION`; releases and their changes are listed at
https://github.com/jp-schneider/agent-devcontainer/releases. `update-from-template.sh` merges a
template release into your repo and leaves the result uncommitted, so you review it first.

- [Quick start](#quick-start)
- [Usage](#usage)
- [What the script does](#what-the-script-does)
- [Whose files are whose](#whose-files-are-whose)
- [History: merge base and squash merges](#history-merge-base-and-squash-merges)
- [Ignored files in the way](#ignored-files-in-the-way)
- [What adopting changes](#what-adopting-changes)
- [Problems](#problems)

## Quick start

On the host, from the repository root, with a clean working tree:

```bash
bash .devcontainer/update-from-template.sh           # latest release (vX.Y.Z tag)
git status                                           # conflicts, if any
git diff --cached                                    # review
git commit                                           # message is prepared
```

Then push and open a PR as usual. **Merge the update PR with a merge commit, not squash**; see
[History](#history-merge-base-and-squash-merges). To undo an update before committing:
`git merge --abort`.

## Usage

```
bash .devcontainer/update-from-template.sh [--adopt] [--ignored=<mode>] [<ref>] [<template-url>]
```

| Argument | Meaning |
|---|---|
| `<ref>` | What to merge: a release tag (`v0.2.0`) or a branch name (e.g. to try an unreleased fix). Default: the latest `vX.Y.Z` tag of the template, or `main` if there is none. |
| `<template-url>` | Where the template lives. Default: `https://github.com/jp-schneider/agent-devcontainer.git`. Only used when the repo has no remote named `template` yet; an existing `template` remote is used as it is (change it with `git remote set-url template <url>`). |
| `--adopt` | First merge into a repository that wasn't created from the template. See [What adopting changes](#what-adopting-changes) and [Getting started, B](getting-started.md#b-existing-repository). |
| `--ignored=<mode>` | What to do with [ignored files in the way](#ignored-files-in-the-way): `ask`, `abort`, `backup` or `overwrite`. Default: `ask` in a terminal, `abort` otherwise. |

Options come before `<ref>`. Unknown options are refused. Examples:

```bash
bash .devcontainer/update-from-template.sh v0.2.0                     # a specific release
bash .devcontainer/update-from-template.sh fix-something              # a branch of the template
bash .devcontainer/update-from-template.sh --ignored=backup           # non-interactive, keep a copy
bash .devcontainer/update-from-template.sh main https://github.com/<you>/<fork>.git   # a fork
```

## What the script does

1. **Checks the working tree.** Anything uncommitted stops it: commit or stash first. Changes
   inside submodules (and new submodule commits you haven't staged) don't count and stay as they
   are. With `--adopt` it also needs at least one commit, and refuses repos that already have
   the template.
2. **Fetches** `<ref>` from the `template` remote (added if missing).
3. **Checks for [ignored files in the way](#ignored-files-in-the-way)** and handles them per
   `--ignored`. Nothing has changed up to here.
4. **Prints the version change** (e.g. `0.1.0 -> 0.2.0 (ref v0.2.0)`) and **merges** without
   committing. Without shared history it uses the release in `VERSION` as the merge base
   ([History](#history-merge-base-and-squash-merges)).
5. **Resolves what it can:** keeps [your own files](#whose-files-are-whose), drops template-only
   files, merges `.gitignore` (your lines, plus the template's missing ones under
   `# devcontainer template`). `.devcontainer/VERSION` takes the template's value.
6. **Reports:** tracked files that are now ignored (check them for secrets, then
   `git rm --cached <file>`), and the conflicts left to you. git's own merge report is not shown,
   because it lists conflicts the script resolves itself.

The result is a staged merge (`MERGE_HEAD` set), so `git commit` creates a merge commit with the
template as second parent, and `git merge --abort` returns to where you were.

## Whose files are whose

| Path | Owner | On update |
|---|---|---|
| `.devcontainer/` (except the two below) | template | merged; your edits there can conflict |
| `.devcontainer/compose.project.yml`, `.devcontainer/apt-packages.txt` | you | never touched |
| `.devcontainer/mask-patterns.txt`, `.devcontainer/allowed-nested-git.txt` | you | not in the template, never touched |
| `README.md`, `CLAUDE.md`, `.claude/`, `docs/` (repo root), `LICENSE` | you | never touched (the template's `LICENSE` goes to `.devcontainer/LICENSE`) |
| template-only files (tests, template docs, policies, CI, release scripts) | template repo | never added to your repo |
| `.vscode/settings.json`, `.mcp.json` | template | merged; keep `"git.autoRepositoryDetection": false` when resolving |
| `.gitignore` | both | union, see step 5 |
| everything else | you | the template has nothing there |

The root `docs/` is yours; `.devcontainer/docs/` (these pages) is the template's and updates with
it. To change the container setup, prefer the files you own; see
[customizing.md](customizing.md#ground-rules). **Deleted variants** come back if the template
changed them; delete them again.

## History: merge base and squash merges

Repos created with "Use this template" have no shared git history with the template. On the
**first update**, and after an update that was **squash-merged**, the script therefore uses the
template release named in `.devcontainer/VERSION` as the merge base (it prints
`merge base: vX.Y.Z`). Only files you changed since that release can conflict.

- **`VERSION` names no release** (e.g. you started from an unreleased `main` or a branch): there is
  no base, and every file that differs from the template conflicts. Resolve them once; later
  updates are normal again.
- **The commit links the histories:** the template becomes a merge parent, so the next update has
  a common ancestor and needs no base from `VERSION`. A squash merge of the update PR drops that
  link again (the next update then falls back to `VERSION`, which works but costs the extra step).

## Ignored files in the way

git treats ignored files as expendable: an ignored file at a path where the template has a file
your repo doesn't track (or a file where the template has a directory) would be overwritten without
notice. The script lists such files before merging and then, by `--ignored`:

| Mode | Effect |
|---|---|
| `ask` | In a terminal: `[a]bort`, `[b]ack up all`, `[o]verwrite all`, or decide for `[e]ach` file (`[b]ack up`, `[o]verwrite`, `[a]bort`). Nothing changes until every answer is given; end of input counts as abort. |
| `abort` | Stop, nothing changed. Move the files away and run again. |
| `backup` | Rename each to `<name>.bak` (`.bak.1`, `.bak.2`, … if taken), then merge. |
| `overwrite` | Delete them, then merge. |

`--ignored=ask` without a terminal reads the answers from stdin. Ignored files elsewhere (build
output, `.env`, venvs) are not affected and don't stop the update.

## What adopting changes

`--adopt` is for the first merge into a repository that wasn't created from the template. The
steps: [Getting started, B](getting-started.md#b-existing-repository).

On top of a normal [update](#what-the-script-does), `--adopt`:
- **moves your previous devcontainer config** (everything tracked under `.devcontainer/`, and a root
  `.devcontainer.json`) to `.devcontainer.legacy/`. VS Code doesn't look there;
- **adds missing files** from the template, never overwriting yours: `.devcontainer/compose.project.yml`
  (every variant needs it), `.devcontainer/apt-packages.txt` (empty), `.claude/settings.json` (deny rules), and a generic `CLAUDE.md`,
  `.claude/overview.md`, `.claude/memory/MEMORY.md`. Files your `.gitignore` ignores are skipped;
- **lists tracked files that are now ignored**;
- refuses to run if the repo already has the template (`.devcontainer/VERSION`),
  `.devcontainer.legacy/` exists, or the repo already shares history with the template.

Your own `README.md` and `.claude/` are kept, as on updates.

This is a real merge, so the template's commits become part of your history (`git log --first-parent`
hides them). In return, later updates have a common ancestor and merge normally, with the plain
`bash .devcontainer/update-from-template.sh`.

## Problems

| Message or symptom | Cause / fix |
|---|---|
| `working tree not clean, commit or stash first` | Uncommitted or staged changes (a staged submodule commit counts too). Commit or stash, then run again. |
| `ignored local files are in the way of template files` | See [Ignored files in the way](#ignored-files-in-the-way). |
| `merge did not start, see git's message above` | git refused before changing anything (rare: the checks before the merge catch the usual causes). Fix what git reports and run again. |
| `unknown option` | Options are `--adopt` and `--ignored=ask\|abort\|backup\|overwrite`, before `<ref>`. |
| `this repo already has the template` / `already shares history with the template; run without --adopt` | `--adopt` is only for the first merge. Run without it. |
| Almost every file conflicts | No merge base: `VERSION` names no release, see [History](#history-merge-base-and-squash-merges). |
| `.vscode/settings.json` conflicts | Keep your settings and `"git.autoRepositoryDetection": false`. |
| A deleted variant is back | The template changed it. Delete it again before committing. |
| The wrong template is fetched | An existing `template` remote wins over `<template-url>`: `git remote -v`. |
