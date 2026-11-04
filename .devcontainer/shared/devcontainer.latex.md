## LaTeX
Only applies when the variant includes the latex toolchain (`DEVCONTAINER_TOOLCHAINS` contains `latex`).

- **TeX Live $TEXLIVE_YEAR from upstream**, in a volume shared with the user's other projects
  (`$TEXLIVE_ROOT`), installed at container start: a curated set, not scheme-full. pdfLaTeX,
  LuaLaTeX, XeLaTeX, latexmk, biber, chktex, latexindent. Build with
  `latexmk -pdf -interaction=nonstopmode -file-line-error <file>.tex` (`-lualatex`/`-xelatex` for the
  other engines); the user's editor (LaTeX Workshop) builds with latexmk on save. If `latexmk` is
  missing, the first install is still running or failed: see the start log or
  `$TEXLIVE_ROOT/install-$TEXLIVE_YEAR.log`, and tell the user.
- **Missing package** (`! LaTeX Error: File 'x.sty' not found`): `tlmgr search --global --file x.sty`
  names the package. For the project, ask the user to add it to `.devcontainer/tex-packages.txt`
  (read-only to you; installed at the next start). For a quick try, `tlmgr install <pkg>` works,
  but say so: it changes TeX Live for all of the user's projects, and only the list is reproducible.
  Don't vendor packages into the project without asking.
- **No `-shell-escape`** unless the user asks (minted, some externalisation setups need it): it lets
  the document run arbitrary commands.
- Build artefacts (`*.aux`, `*.log`, `*.fdb_latexmk`, `*.fls`, `*.synctex.gz`, ...) don't belong in
  git; `latexmk -c` removes them.
