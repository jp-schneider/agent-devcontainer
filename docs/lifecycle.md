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
- Removes `docs/` and `.claude/{plans,scratchpad,knowledge,memory}`. Other `.claude/` files,
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
2. Adds the `template` remote if needed and fetches the branch (default
   `https://github.com/jp-schneider/devcontainer.git`, `main`).
3. `git merge --no-commit --no-ff`, with `--allow-unrelated-histories` if there is no merge base
   (the first update).
4. For each **repo-owned path** (`CLAUDE.md README.md .claude docs .github/template-cleanup
   .devcontainer/compose.project.yml`):
   - if the derived repo has it, removes files the template *added* under it and restores the
     repo's version (this also resolves conflicts there);
   - otherwise removes the template's copy.

   Only tracked files are touched, so ignored files like `.claude/settings.local.json` survive.
5. Leaves the merge staged and lists remaining conflicts. The user reviews and commits.

**Why not re-run the cleanup after a merge?** An earlier design did that ("self-healing"). It
would overwrite the derived repo's customized `CLAUDE.md` and `README.md` and delete its own plans.

**Expected friction:**
- The first update conflicts (add/add) on every file that differs between the two sides, because
  there is no common ancestor. Later updates merge normally.
- Variants deleted in the derived repo come back if the template changed them.
