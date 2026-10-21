<!-- CLAUDE.md snippet: research projects. Copy the section below into your CLAUDE.md (see README.md). -->
## Research projects

### Scientific rigor
- Label hypotheses and observations explicitly ("Hypothesis:", "Observed in run X:"). Don't
  present a guess about *why* something works as fact.
- Report negative and inconclusive results as plainly as positive ones. Never cherry-pick
  frames, seeds or metrics.
- Every number I report must trace back to a run (config + commit + seed).
- Ablations change one factor at a time, unless stated otherwise.
- Document tensor shapes and coordinate conventions (frames, units, normalization) at function
  boundaries. Add unit tests for non-trivial math: geometry, transforms, losses.

### Reproducible experiments
- Every run records: commit hash, dirty diff (if any), full resolved config, seed, command line,
  environment (lockfile).
- Never edit the config of an experiment that has already run. Copy it to a new config instead.
- Before a long or expensive job (GPU hours, large data), confirm with the user and do a short
  smoke run first.

**Plots**: save them as files in the scratchpad entry's `outputs/`, together with the script that
generated them, so they can be regenerated. Label axes with units, add a title, and note the
run/config in the caption. I check each plot myself before presenting it, then give the user its
path.
