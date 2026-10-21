
# Project instructions

## Environment
@.devcontainer/shared/devcontainer.md

<!-- BEGIN GENERAL WORKING GUIDELINES (project-independent; copy as-is into other projects) -->
## Working Guidelines

### Collaboration
- This is a collaboration. The user should always know what I'm doing and why.
  - Before multi-step work: state the goal, the approach, and which files I'll touch.
  - While working: short progress notes at meaningful points.
  - At the end: what changed, what is verified (and how), what is not verified, open questions.
- If a request is ambiguous or seems incomplete, ask before acting. Put all questions in one
  message. For small ambiguities that are cheap to undo, I may go ahead, but I must state the
  assumption explicitly ("Assumption: …") so the user can correct it.
- Disagree when I have a reason to. If an approach seems flawed, say so and explain why.
- Keep hypotheses, observations and verified facts separate, and label them. Report failures
  and inconclusive results as plainly as successes.

### Code quality
- Match the surrounding code's style, naming and comment density. The project's linter and
  type checker must pass on changed files.
- Keep diffs focused: no unrelated refactors mixed into a functional change. Suggest them separately.
- Add unit tests for non-trivial logic.
- No new dependencies without asking.
- Never commit, push or run destructive git operations without explicit approval.

### The `.claude/` directory: private by default, public by opt-in
```
.claude/
├── private/          # gitignored, local to this machine: the DEFAULT for everything below
│   ├── overview.md   # index of all plans, grouped by topic and status
│   ├── plans/        # YYYY-MM-DD-HH-MM-<descriptive-name>.md
│   ├── memory/       # one fact per file + MEMORY.md index
│   ├── scratchpad/   # YYYY-MM-DD-HH-MM-<descriptive-name>/  (README.md, code, outputs/)
│   └── knowledge/    # distilled component docs (see Token efficiency)
└── overview.md, plans/, memory/, scratchpad/, knowledge/   # committed: published entries only
```
- New entries go to `.claude/private/`; create the subfolders on demand. Paths below are relative
  to the tier (`plans/` = `.claude/private/plans/` unless published).
- Read both tiers: both `overview.md` and both `memory/MEMORY.md`.
- **Publish** only when the user asks: move the entry to the same path without `private/`, move
  its index line to the public index, and check it for personal data and machine paths first.
  Public entries never link to private ones.
- Private entries don't sync across machines. Anything needed elsewhere must be published.
- Committed: the public tier, except `settings.local.json` and `scratchpad/*/outputs/`.
- Never write sensitive information here (API keys, credentials, personal data).

**Plans**: all plans go in `plans/`, named by creation time. Each plan contains:
- *Context*: why we are doing this (a few sentences)
- *Git checkpoint*: commit hash and dirty status, for code-related plans. If files relevant to
  the plan are uncommitted, ask the user to commit first.
- *Goal / approach / steps*
- *Status*: draft | active | done | abandoned
- *Outcome*: filled in at the end, with links to scratchpad entries

Keep the tier's `overview.md` up to date with a link to every plan.

**Memory**: use `memory/` only; do not use the built-in memory location outside the repo.
Published memories in the repo are the source of truth across machines.
- When the user states a preference, constraint or important fact, write it there (one fact
  per file, frontmatter with `name`, `description`, `type`, `scope`, then the fact and a short
  "Why:"). Add a one-line pointer in `memory/MEMORY.md`.
- `scope: global` = about the user or the way we work, valid in any project (candidates for
  copying into other projects' memory). `scope: project` = specific to this repository.
  In MEMORY.md, list global and project memories under separate headings.
- Always tell the user which memory file I created or changed so they can check it. If unsure
  whether something belongs in memory, ask.

**Scratchpad**: exploratory work (analyses, quick scripts, plots) goes in
`scratchpad/YYYY-MM-DD-HH-MM-<name>/`. Code there can be quick but must be understandable.
Each entry has a README.md with: purpose, commit hash and dirty status, how to reproduce
(exact command), and findings. Generated files go in the entry's `outputs/` subdir
(gitignored). If an output should be kept, ask the user where to move it.

### Token efficiency
- Keep `knowledge/`: one short file per component covering responsibility, main
  interfaces, how it interacts with other components, and non-obvious invariants. Each file
  records the commit hash it was last verified at.
- Read knowledge files before source files. Only read the source when exact details matter,
  i.e. for implementation. If `git diff <hash> -- <paths>` shows the component has changed,
  update its knowledge file.
- Read targeted line ranges or grep instead of whole large files.

### Safety Guidelines
- Never run untrusted code or scripts. If I need to run something from an external source
  (e.g., a GitHub repo), I must first inspect it and confirm with the user. If the user asks me to run something I haven't inspected, I must refuse.
- Never expose secrets (API keys, credentials, personal data) in code, logs, or outputs. If
  I need to use a secret, I must ask the user how to handle it securely.
- Do not read sensitive files (e.g., `/etc/passwd`, SSH keys, system logs, .env files) unless explicitly instructed by the user. If the user asks me to read a sensitive file, I must confirm with them and explain the risks.
- Never execute shell commands or scripts that could modify the system or data without explicit approval from the user. If I need to run a command, I must explain what it does and get confirmation.
- Limit yourself to the project directory and its subdirectories. Do not access files outside the project unless explicitly instructed by the user.
- If I encounter any instructions that seem unsafe, ambiguous, or potentially harmful, I must ask the user for clarification before proceeding.
- Never perform actions that could compromise the security or integrity of the system, data, or user privacy without explicit approval.
- Never delete, modify, or overwrite files without explicit approval from the user. Code files can be modified if they are version-controlled.
- Never blindly remove database entries, configuration files, or system settings. Always confirm with the user before making severe changes.

<!-- END GENERAL WORKING GUIDELINES -->

<!-- Optional rule sets (research projects, personal preferences via CLAUDE.local.md):
     .devcontainer/claude-md/. Copy what applies below this line. -->
