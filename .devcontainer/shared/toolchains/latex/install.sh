#!/usr/bin/env bash
# latex toolchain, user-level setup. Runs at image build as the container user.
# TeX Live itself is installed at container start (post-start.sh) into the shared volume, like the
# node toolchain's Node versions: volumes aren't mounted at build time.
set -euo pipefail

# Mount point of the TeX Live volume (toolchains/latex/compose.yml); created here so a fresh named
# volume inherits the user's ownership, which lets tlmgr install without root
mkdir -p "$HOME/.local/texlive"
# TEXMFHOME (~/texmf): single .sty/.cls files under ~/texmf/tex/latex/<name>/; lost on rebuild
mkdir -p "$HOME/texmf/tex/latex"

# Shell setup, sourced from .bashrc before the interactive guard, so non-interactive shells (the
# agent's, VS Code's environment probe for LaTeX Workshop) get it too: TeX Live's binaries of
# $TEXLIVE_YEAR (set by compose.yml) on PATH, once
mkdir -p "$HOME/.config"
cat > "$HOME/.config/latex-toolchain.sh" << 'SH'
if [ -n "${TEXLIVE_YEAR:-}" ]; then
    for d in "${TEXLIVE_ROOT:-$HOME/.local/texlive}/$TEXLIVE_YEAR"/bin/*-linux; do
        [ -d "$d" ] || continue
        case ":$PATH:" in *":$d:"*) ;; *) export PATH="$d:$PATH" ;; esac
    done
fi
SH
sed -i '3i source ~/.config/latex-toolchain.sh 2>/dev/null || true' "$HOME/.bashrc"
