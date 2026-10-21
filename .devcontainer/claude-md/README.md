# CLAUDE.md snippets

Optional rule sets for `CLAUDE.md`, for kinds of projects the generic `CLAUDE.md` doesn't
assume. Copy what applies into your `CLAUDE.md` (or `CLAUDE.local.md`) and adapt it. These files
are not imported automatically. `update-from-template.sh` keeps them current, but your copies are
yours.

| File | For | Goes into |
|---|---|---|
| [research.md](research.md) | ML / research code: scientific rigor, reproducible runs, plots | `CLAUDE.md`, after the general guidelines |
| [personal-preferences.md](personal-preferences.md) | Who you are and how you like to work, without committing it | `CLAUDE.local.md` (gitignored), imported from `CLAUDE.md` |

New snippets are welcome (see the template's CONTRIBUTING.md): one file per kind of project,
written as instructions to the agent, with nothing project- or person-specific in it.
