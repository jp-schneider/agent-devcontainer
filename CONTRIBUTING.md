# Contributing

Thanks for considering a contribution! This template is maintained by one person without a
professional security background, so **every review, question and fix helps**, whatever your
experience level. "I'm not sure this is safe because …" is a perfectly good issue.

**Security vulnerabilities:** please don't open a public issue. See [SECURITY.md](SECURITY.md).

## Ways to contribute

- **Security review:** read [docs/security.md](docs/security.md) and try to break it. Look for
  escape paths, wrong assumptions, or missing threats.
- **Close a known limitation:** see [.devcontainer/README.md](.devcontainer/README.md#known-limitations),
  e.g. egress filtering or pinning the supply chain.
- **Test on other hosts:** native Linux, macOS, other GPUs. Report what worked and what didn't.
- **New variants and toolchains:** see [docs/extending.md](docs/extending.md).
- **Docs and usability:** anything that confused you is worth fixing.

For larger changes, please open an issue first so we can agree on the approach.

## Development setup

1. Fork and clone the repository, then open it in VS Code → "Reopen in Container" and pick the
   **`template-dev`** variant. It has what the tests and CI need (shellcheck, Python 3 + PyYAML;
   `tests/run.sh` fetches the pinned bats) and the bats and shellcheck VS Code extensions.
2. To let a coding agent edit the template itself (`.devcontainer/` is read-only in the container
   by design), set this in `.env` on the host:
   ```
   DEVCONTAINER_EDITABLE_BY_AGENT=1
   ```
   Then **review `git diff -- .devcontainer` before every container restart**: those files run on
   your host.

Orientation: [docs/README.md](docs/README.md) (layout, design decisions) and
[docs/architecture.md](docs/architecture.md).

## Testing

**Automated tests** run inside the container; no Docker is needed:

```bash
tests/run.sh
```

- **Framework:** bats-core, a pinned dev dependency. `tests/run.sh` fetches it if needed.
- **CI** runs the same suites on every pull request, on Ubuntu (plus `shellcheck`) and on macOS
  with bash 3.2.
- **Details and rules for writing tests:** [docs/testing.md](docs/testing.md#automated-tests-tests-bats).
- **New behaviour needs a test,** including a negative control.

**Host checks** need a real build and start. Follow the checklist in
[docs/testing.md](docs/testing.md#host-checks) for the variants and hosts your change affects.

## Invariants: please keep these intact

These are easy to break by accident and matter for security:

- **Compose file order in every variant:** `shared/compose.core.yml` first, then overlays,
  `compose.project.yml`, `.generated/compose.host.yml`, and **`.generated/compose.protect.yml`
  last**.
- **The variants' security settings stay identical:** `remoteEnv` and the VS Code security
  settings are duplicated in each `devcontainer.json` (there's no include mechanism).
- **Paths the host executes or trusts are protected** in `shared/protect-paths.sh`, not left
  writable or handled in an overlay.
- **Host-side scripts stay bash 3.2 compatible** (macOS): `initialize.sh`, `host-override.sh`,
  `protect-paths.sh`, `resolve-config.sh`, `toolchains/*/init-host.sh`, `update-from-template.sh`,
  `cleanup.sh`.
- **The three secret-file lists stay in sync:** `shared/mask-patterns.txt` (regex, the actual
  protection), `shared/claude-settings.default.json` (deny globs) and the variants'
  `files.exclude`.
- **Nothing that widens access by default:** no `privileged`, no extra capabilities, no
  credential or Docker-socket mounts. Make it opt-in and document the trade-off.
- **Template-only vs. kept files:** derived repos keep `.devcontainer/`. The cleanup removes
  `docs/`, `tests/`, `.vscode/tasks.json`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md` and `.github/ISSUE_TEMPLATE/`, and
  `update-from-template.sh` never merges them back. Put user-facing content in `.devcontainer/`.

## Pull request checklist

- [ ] The change is explained: what it protects against, or why it's safe.
- [ ] `tests/run.sh` passes (CI too). Host checks were done for the affected variants/hosts, or are listed
      as not done.
- [ ] Docs updated: `.devcontainer/README.md` (including **Known limitations** if the security
      picture changes), `CUSTOMIZING.md`, `REFERENCE.md` and `docs/` as needed.
- [ ] `CHANGELOG.md`: an entry under **[Unreleased]**. No version bump, unless the PR is meant to be
      a release (maintainer, see below).

## Releases (maintainer)

Versions follow [SemVer](https://semver.org/); while at 0.x, a minor version may break things,
with migration notes in the changelog.

**Only a PR that ran `prepare.sh` is a release.** Every other PR adds its CHANGELOG entry under
**[Unreleased]** and releases nothing when merged; its changes ship with the next release. A
release is then one pull request: it bumps the version, and merging it publishes the release.

1. **Bump the version in a PR**, either as the last commit of a feature PR or in a small PR of
   its own, on a branch from `main`, with a clean working tree:
   ```bash
   bash .github/release/prepare.sh x.y.z   # commits "Release vx.y.z", prints the release notes
   ```
   [prepare.sh](.github/release/prepare.sh) sets `.devcontainer/VERSION`, turns **[Unreleased]**
   into `## [x.y.z] - YYYY-MM-DD` under a new empty **[Unreleased]**, and commits both files. It
   refuses a dirty working tree (untracked files included), an existing version or an empty
   **[Unreleased]**. Run `tests/run.sh` afterwards: CI does the same on the PR.
2. **Merge** once CI is green (squash).
3. **Done:** [release.yml](.github/workflows/release.yml) sees the changed `VERSION` on `main`,
   checks it ([version-to-release.sh](.github/release/version-to-release.sh): no existing tag
   `vx.y.z`, greater than every release, a dated CHANGELOG section), then creates the tag and the
   GitHub release with that section as notes. An inconsistent bump fails the workflow instead;
   fix it in a new PR.

The workflow pushes nothing to `main` (a protected `main` is fine), only the tag. **GitHub setup:**
a tag ruleset for `v*` that blocks updating and deleting tags but not creating them, so releases
can't be moved afterwards and the workflow can still create them.

Derived repos update with `.devcontainer/update-from-template.sh`, which defaults to the latest
release tag.

## License

By contributing, you agree that your contributions are licensed under the repository's
[MIT License](LICENSE).
