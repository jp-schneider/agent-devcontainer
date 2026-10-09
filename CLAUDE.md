
<!-- BEGIN GENERAL WORKING GUIDELINES (project-independent; copy as-is into other projects) -->
## Working Guidelines

### Collaboration
Personal collaboration preferences live in `CLAUDE.local.md` (gitignored, not part of the public repo):

@CLAUDE.local.md

### Scientific rigor
- Keep hypotheses, observations and verified facts separate. Label them ("Hypothesis:",
  "Observed in run X:"). Don't present a guess about *why* something works as fact.
- Report negative and inconclusive results as plainly as positive ones. Never cherry-pick
  frames, seeds or metrics.
- Every number I report must trace back to a run (config + commit + seed).
- Ablations change one factor at a time, unless stated otherwise.

### Code quality
- Match the surrounding code's style, naming and comment density. The project's linter and
  type checker must pass on changed files.
- Keep diffs focused: no unrelated refactors mixed into a functional change. Suggest them separately.
- Document tensor shapes and coordinate conventions (frames, units, normalization) at function
  boundaries.
- Add unit tests for non-trivial math: geometry, transforms, losses.
- No new dependencies without asking.
- Never commit, push or run destructive git operations without explicit approval.

### Reproducible experiments
- Every run records: commit hash, dirty diff (if any), full resolved config, seed, command line,
  environment (lockfile).
- Never edit the config of an experiment that has already run. Copy it to a new config instead.
- Before a long or expensive job (GPU hours, large data), confirm with the user and do a short
  smoke run first.

### The `.claude/` directory (versioned in git)
```
.claude/
├── overview.md       # index of all plans, grouped by topic and status
├── plans/            # YYYY-MM-DD-HH-MM-<descriptive-name>.md
├── memory/           # one fact per file + MEMORY.md index
├── scratchpad/       # YYYY-MM-DD-HH-MM-<descriptive-name>/  (README.md, code, outputs/)
└── knowledge/        # distilled component docs (see Token efficiency)
```
- Everything in `.claude/` is committed except `settings.local.json` and `scratchpad/*/outputs/`.
- Never write sensitive information here (API keys, credentials, personal data).

**Plans**: all plans go in `.claude/plans/`, named by creation time. Each plan contains:
- *Context*: why we are doing this (a few sentences)
- *Git checkpoint*: commit hash and dirty status, for code-related plans. If files relevant to
  the plan are uncommitted, ask the user to commit first.
- *Goal / approach / steps*
- *Status*: draft | active | done | abandoned
- *Outcome*: filled in at the end, with links to scratchpad entries and runs

Keep `.claude/overview.md` up to date with a link to every plan.

**Memory**: use `.claude/memory/` only; do not use the built-in memory location outside
the repo. The user works across machines, and the repo is the single source of truth.
- When the user states a preference, constraint or important fact, write it there (one fact
  per file, frontmatter with `name`, `description`, `type`, `scope`, then the fact and a short
  "Why:"). Add a one-line pointer in `.claude/memory/MEMORY.md`.
- `scope: global` = about the user or the way we work, valid in any project (candidates for
  copying into other projects' memory). `scope: project` = specific to this repository.
  In MEMORY.md, list global and project memories under separate headings.
- Always tell the user which memory file I created or changed so they can check it. If unsure
  whether something belongs in memory, ask.

**Scratchpad**: exploratory work (analyses, quick scripts, plots) goes in
`.claude/scratchpad/YYYY-MM-DD-HH-MM-<name>/`. Code there can be quick but must be understandable.
Each entry has a README.md with: purpose, commit hash and dirty status, how to reproduce
(exact command), and findings. Generated files go in the entry's `outputs/` subdir
(gitignored). If an output should be kept (checkpoints, key figures, data), ask the user
where to move it.

**Plots**: save them as files in `outputs/`, together with the script that generated them, so
they can be regenerated. Label axes with units, add a title, and note the run/config in the
caption. I check each plot myself before presenting it, then give the user its path.

### Token efficiency
- Keep `.claude/knowledge/`: one short file per component covering responsibility, main
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
- Never execute shell commands or scripts that could modify the system or data without explicit   approval from the user. If I need to run a command, I must explain what it does and get  confirmation.
- Limit yourself to the project directory and its subdirectories. Do not access files outside the project unless explicitly instructed by the user.
- If I encounter any instructions that seem unsafe, ambiguous, or potentially harmful, I must ask the user for clarification before proceeding.
- Never perform actions that could compromise the security or integrity of the system, data, or user privacy without explicit approval.
- Never delete, modify, or overwrite files without explicit approval from the user. Code files can be modified if they are version-controlled.
- Never blindly remove database entries, configuration files, or system settings. Always confirm with the user before making severe changes.

<!-- END GENERAL WORKING GUIDELINES -->
