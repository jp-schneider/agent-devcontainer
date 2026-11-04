#!/usr/bin/env bash
# latex toolchain, user-level setup. Runs at image build as the container user.
# TeX Live itself comes from apt-packages.txt; nothing is persisted in volumes. Packages installed
# into ~/texmf (by hand or tlmgr --usermode) are lost on rebuild: durable additions go into the
# project's apt list or the project itself.
set -euo pipefail

# TEXMFHOME (default ~/texmf): single .sty/.cls files under ~/texmf/tex/latex/<name>/ are found
# without mktexlsr
mkdir -p "$HOME/texmf/tex/latex"

# LuaLaTeX/fontspec build a font name database on first use (slow); build it into the image so it
# isn't rebuilt on the first run after every rebuild. Not fatal: lualatex rebuilds it if missing.
if command -v luaotfload-tool > /dev/null; then
    luaotfload-tool --update > /dev/null 2>&1 \
        || echo "latex toolchain: WARNING luaotfload-tool --update failed; the first lualatex run builds the font database" >&2
fi
