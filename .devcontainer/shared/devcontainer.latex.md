## LaTeX
Only applies when the variant includes the latex toolchain (`DEVCONTAINER_TOOLCHAINS` contains `latex`).

- **TeX Live 2023 from Ubuntu's apt packages**, a curated set (not `texlive-full`): pdfLaTeX,
  LuaLaTeX, XeLaTeX, latexmk, biber, chktex, latexindent. Build with
  `latexmk -pdf -interaction=nonstopmode -file-line-error <file>.tex` (`-lualatex`/`-xelatex` for the
  other engines); the user's editor (LaTeX Workshop) builds with latexmk on save.
- **Missing package** (`! LaTeX Error: File 'x.sty' not found`): `kpsewhich x.sty` confirms it;
  `apt-file` isn't installed, so name the likely `texlive-*` bundle and ask the user to add it to
  `.devcontainer/apt-packages.txt` and rebuild. Don't vendor a package into the project without
  asking. `tlmgr` doesn't manage the system TeX Live.
- **No `-shell-escape`** unless the user asks (minted, some externalisation setups need it): it lets
  the document run arbitrary commands.
- Build artefacts (`*.aux`, `*.log`, `*.fdb_latexmk`, `*.fls`, `*.synctex.gz`, ...) don't belong in
  git; `latexmk -c` removes them.
