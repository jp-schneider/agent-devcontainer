# Template lifecycle

## 1. Creating a repo from the template

"Use this template" on GitHub creates a new repo with the template's tree as a single commit and
**no shared history**. GitHub has no way to exclude files from the copy
([community discussion #22183](https://github.com/orgs/community/discussions/22183)), so
template-only files are removed afterwards by a workflow.

## 2. Cleanup workflow

[.github/workflows/template-cleanup.yml](../.github/workflows/template-cleanup.yml) runs
[cleanup.sh](../.github/template-cleanup/cleanup.sh) once and commits the result.

**What it does:**
- Removes the template-only `docs/`, `tests/`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`,
  `.github/ISSUE_TEMPLATE/` and `.claude/{plans,scratchpad,knowledge,memory}`. Other `.claude/` files,
  e.g. `settings.json`, are kept.
- Writes fresh `.claude/overview.md` and `.claude/memory/MEMORY.md`.
- Replaces `CLAUDE.md` with the generic version: no personal persona, and research rules in an
  optional block.
- Replaces `README.md` with a stub: the repo name, a random line from `files/jokes.txt`, and a
  link to `.devcontainer/README.md`.
- Deletes `.github/template-cleanup/` itself. This directory is the "not yet cleaned" marker.

**Triggers and guards:**
- `push`, `create`, `workflow_dispatch`. Which events fire on template creation isn't documented,
  so the workflow listens to all of them.
- `if: github.repository != 'jp-schneider/devcontainer' && github.ref_type == 'branch'`.
  **Update this if the template repo is renamed.**
- The job exits early if the marker directory is gone. Together with a `concurrency` group
  (no cancellation) and checking out the branch tip (`ref: github.ref`, not the triggering SHA),
  a second queued run is a no-op.
- `run_number == 1`, used in the discussion's example, was reported as unreliable and is not used.

**Permissions and limits:**
- `contents: write`. If an org or repo restricts `GITHUB_TOKEN` to read-only, the push fails, and
  the user runs `bash .github/template-cleanup/cleanup.sh` by hand.
- The workflow file stays in derived repos. *Belief, unverified:* a `GITHUB_TOKEN` push cannot
  modify `.github/workflows/`, so the workflow cannot delete itself.
- No third-party actions; `actions/checkout` is pinned by SHA (v6.1.0).

## 3. Pulling template updates

[update-from-template.sh](../.devcontainer/update-from-template.sh), run from the root of the
derived repo:

1. Refuses to run on a dirty tree.
2. Adds the `template` remote if needed (default URL `https://github.com/jp-schneider/devcontainer.git`)
   and fetches the ref: the first argument (tag or branch). By default it picks the **latest
   `vX.Y.Z` tag**, falling back to `main` if there are none. It prints the version change from
   `.devcontainer/VERSION`.
3. `git merge --no-commit --no-ff`, with `--allow-unrelated-histories` if there is no merge base
   (the first update). Stops if the merge didn't start (no `MERGE_HEAD`).
4. For each **repo-owned path** (`CLAUDE.md README.md .claude docs .github/template-cleanup
   .devcontainer/compose.project.yml SECURITY.md CONTRIBUTING.md CHANGELOG.md .github/ISSUE_TEMPLATE tests
   .github/workflows/tests.yml .github/workflows/template-cleanup.yml`):
   - if the derived repo has it, removes files the template *added* under it and restores the
     repo's version (this also resolves conflicts there);
   - otherwise removes the template's copy.

   Only tracked files are touched, so ignored files like `.claude/settings.local.json` survive.
   `.devcontainer/VERSION` always takes the template's value (it would otherwise conflict on the
   first, unrelated merge).
   A conflicted `.gitignore` is resolved as ours plus the template's missing lines.
5. Leaves the merge staged and lists remaining conflicts. The user reviews and commits.

**Why not re-run the cleanup after a merge?** An earlier design did that ("self-healing"). It
would overwrite the derived repo's customized `CLAUDE.md` and `README.md` and delete its own plans.

**Expected friction:**
- The first update conflicts (add/add) on every file that differs between the two sides, because
  there is no common ancestor. Later updates merge normally.
- Variants deleted in the derived repo come back if the template changed them.

## 4. Adopting the template in an existing repo

`update-from-template.sh --adopt` is the first merge for a repo that was **not** created from the
template. Same steps as above, plus:

- **Refusals:** no commit yet; `.devcontainer/VERSION` in HEAD (already a template repo); a shared
  history with the template; an existing `.devcontainer.legacy/`.
- **Legacy config:** every file tracked in HEAD under `.devcontainer/`, plus a root
  `.devcontainer.json`, is staged at `.devcontainer.legacy/<path>` with the same blob and mode
  (`update-index --cacheinfo`). The original path takes the template's version or is removed, so
  `.devcontainer/` is entirely the template's. Not `.devcontainer/legacy/`: VS Code scans
  `.devcontainer/*/devcontainer.json` and would list it as a (broken) variant.
- **Seeding**, only where missing (tracked or on disk) and not ignored:
  `.devcontainer/compose.project.yml` (repo-owned, so otherwise dropped, but every variant lists it),
  `.claude/settings.json` (dropped when the repo already has a `.claude/`), and `CLAUDE.md`,
  `.claude/overview.md`, `.claude/memory/MEMORY.md` from `.github/template-cleanup/files/`. This is
  what "Use this template" plus the cleanup would have provided.
- **Warnings:** tracked files that the merged `.gitignore` now ignores (`git ls-files -ci
  --exclude-standard`), e.g. a committed `.env`; and a hint for the `.vscode/settings.json` conflict.

**Why a real merge, not a squash?** `git merge --squash --allow-unrelated-histories` would keep the
template's commits out of the project history, but leave no merge base: every later update would
again be an unrelated merge, with add/add conflicts on every file the template changed.
`git log --first-parent` hides the template's commits instead.
