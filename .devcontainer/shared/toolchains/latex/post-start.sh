#!/usr/bin/env bash
# latex toolchain, container start (run by shared/post-start.sh). Idempotent; problems are reported
# (WARNING, non-zero exit), they don't stop the start.
# - TeX Live $TEXLIVE_YEAR (compose.yml) in the shared volume at $TEXLIVE_ROOT: installed on the
#   first start on this machine (~1.5 GB download, several minutes), with install-tl from
#   $TEXLIVE_REPOSITORY (default: CTAN's mirror redirector). The installer is only run after its
#   checksum file verified against TeX Live's signing key (fingerprint pinned below); install-tl and
#   tlmgr then verify the package database themselves (gnupg is installed).
# - Packages: the toolchain's tex-packages.txt plus the project's .devcontainer/tex-packages.txt;
#   only missing ones are installed, so later starts don't contact the repository.
# - Concurrent starts of several projects take turns (flock on the volume).
set -uo pipefail

# TeX Live's signing key (primary key fingerprint), as published on
# https://tug.org/texlive/verify.html (taken 2026-11-04). If TeX Live replaces its key, the install
# fails with "signature not by the pinned key"; take the new fingerprint from that page and check
# it against a second source (e.g. a keyserver).
TEXLIVE_GPG_FINGERPRINT=C78B82D8C79512F79CC0D7C80D5E5D9106BAB6BC

year="${TEXLIVE_YEAR:-}"
root="${TEXLIVE_ROOT:-$HOME/.local/texlive}"
repo="${TEXLIVE_REPOSITORY:-https://mirror.ctan.org/systems/texlive/tlnet}"
repo="${repo%/}"
toolchain_list="$(cd "$(dirname "$0")" && pwd)/tex-packages.txt"
project_list="${TEX_PACKAGES_PROJECT:-/app/.devcontainer/tex-packages.txt}"
texdir="$root/$year"
stamp="$texdir/.devcontainer-installed"

warn() { echo "latex post-start: WARNING $*" >&2; }
note() { echo "latex post-start: $*"; }

case "$year" in
    [0-9][0-9][0-9][0-9]) ;;
    *) warn "TEXLIVE_YEAR is '$year', expected a year (set by toolchains/latex/compose.yml)"; exit 1 ;;
esac
if [ ! -d "$root" ] || [ ! -w "$root" ]; then
    warn "$root is missing or not writable (volume not mounted? rebuild the container)"
    exit 1
fi

exec 9> "$root/.lock"
if ! flock -n 9; then
    note "another container is installing into the TeX Live volume, waiting..."
    flock 9
fi

# install_texlive: download, verify, run install-tl (scheme-basic, no docs/sources) into $texdir
install_texlive() {
    local tmp dir status
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064 # expand $tmp now: it is local
    trap "rm -rf '$tmp'" RETURN
    for f in install-tl-unx.tar.gz install-tl-unx.tar.gz.sha512 install-tl-unx.tar.gz.sha512.asc; do
        if ! curl -fsSL --retry 2 -o "$tmp/$f" "$repo/$f"; then
            warn "could not download $repo/$f (offline?); TeX Live is installed on the next start"
            return 1
        fi
    done

    # The key comes with the installer, so it proves nothing by itself: only a signature whose
    # primary key is the pinned one counts. Fresh keyring, nothing else in it.
    export GNUPGHOME="$tmp/gnupg"
    mkdir -m 700 "$GNUPGHOME"
    if ! tar -xzf "$tmp/install-tl-unx.tar.gz" -C "$tmp" --wildcards --no-anchored 'tlpkg/gpg/texlive.asc' 2> /dev/null; then
        warn "installer archive has no tlpkg/gpg/texlive.asc; not installing"
        return 1
    fi
    gpg --batch --quiet --import "$tmp"/install-tl-*/tlpkg/gpg/texlive.asc 2> /dev/null
    if ! gpg --batch --status-fd 1 --verify "$tmp/install-tl-unx.tar.gz.sha512.asc" "$tmp/install-tl-unx.tar.gz.sha512" 2> /dev/null \
        | grep -q "^\[GNUPG:\] VALIDSIG .* $TEXLIVE_GPG_FINGERPRINT\$"; then
        warn "installer checksum: signature not by the pinned key $TEXLIVE_GPG_FINGERPRINT; not installing"
        return 1
    fi
    if ! (cd "$tmp" && sha512sum -c --status install-tl-unx.tar.gz.sha512); then
        warn "installer doesn't match its signed checksum; not installing"
        return 1
    fi
    unset GNUPGHOME
    # Only the directory (the key extracted above); the archive matches install-tl-* too
    rm -rf "$tmp"/install-tl-*/
    if ! tar -xzf "$tmp/install-tl-unx.tar.gz" -C "$tmp"; then
        warn "could not unpack the installer"
        return 1
    fi
    dir="$(echo "$tmp"/install-tl-*/)"
    dir="${dir%/}"
    if ! grep -q "version $year\$" "$dir/release-texlive.txt" 2> /dev/null; then
        warn "the repository has $(head -n 1 "$dir/release-texlive.txt" 2> /dev/null | sed 's/.*version //'), not TeX Live $year." \
            "Update the template (or point TEXLIVE_REPOSITORY at the $year archive:" \
            "https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/$year/tlnet-final)"
        return 1
    fi

    cat > "$tmp/texlive.profile" << EOF
selected_scheme scheme-basic
TEXDIR $texdir
TEXMFLOCAL $root/texmf-local
TEXMFSYSCONFIG $texdir/texmf-config
TEXMFSYSVAR $texdir/texmf-var
TEXMFHOME ~/texmf
TEXMFVAR ~/.texlive$year/texmf-var
TEXMFCONFIG ~/.texlive$year/texmf-config
instopt_adjustpath 0
instopt_adjustrepo 0
tlpdbopt_install_docfiles 0
tlpdbopt_install_srcfiles 0
tlpdbopt_autobackup 0
EOF
    note "installing TeX Live $year into the shared volume (first start on this machine; ~1.5 GB, several minutes); log: $root/install-$year.log"
    "$dir/install-tl" -profile "$tmp/texlive.profile" -repository "$repo" > "$root/install-$year.log" 2>&1
    status=$?
    if [ "$status" -ne 0 ]; then
        warn "install-tl failed (exit $status), last lines of $root/install-$year.log:"
        tail -n 15 "$root/install-$year.log" >&2
        return 1
    fi
    touch "$stamp"
}

if [ ! -f "$stamp" ]; then
    if [ -e "$texdir" ]; then
        note "removing an incomplete TeX Live $year install (interrupted start?)"
        rm -rf "$texdir"
    fi
    if ! install_texlive; then
        rm -rf "$texdir"
        exit 1
    fi
    fresh=1
else
    fresh=0
fi

bindir="$(echo "$texdir"/bin/*-linux)"
if [ ! -x "$bindir/tlmgr" ]; then
    warn "no tlmgr in $texdir/bin; remove $texdir from the volume (or the volume) and restart"
    exit 1
fi
export PATH="$bindir:$PATH"

# Wanted packages: both lists, "#" comments, whitespace-separated. Names restricted to what TeX Live
# uses, so nothing reaches tlmgr as an option.
wanted=""
for list in "$toolchain_list" "$project_list"; do
    [ -f "$list" ] || continue
    for p in $(sed 's/#.*//' "$list"); do
        case "$p" in
            [A-Za-z0-9]*) ;;
            *) warn "skipping '$p' in $list (not a package name)"; continue ;;
        esac
        case "$p" in
            *[!A-Za-z0-9._-]*) warn "skipping '$p' in $list (not a package name)"; continue ;;
        esac
        wanted="$wanted$p
"
    done
done
missing="$(comm -23 <(printf '%s' "$wanted" | grep . | LC_ALL=C sort -u) \
    <(tlmgr info --only-installed --data name 2> /dev/null | LC_ALL=C sort -u))"

status=0
if [ -n "$missing" ]; then
    note "installing $(printf '%s\n' "$missing" | wc -l | tr -d ' ') TeX Live package(s): $(printf '%s' "$missing" | tr '\n' ' ')"
    # tlmgr refuses to install while a newer tlmgr is available: update it first
    # shellcheck disable=SC2086 # one argument per package; names are validated above
    if ! { tlmgr update --self && tlmgr install $missing; }; then
        warn "tlmgr install failed (offline? a package name wrong?). If TeX Live $((year + 1)) is out, its" \
            "repository can't install into $year: update the template. Retried on the next start"
        status=1
    fi
fi

# LuaLaTeX's font database: into TEXMFSYSVAR (the volume), once, so the first lualatex run isn't slow
if [ "$fresh" -eq 1 ] || [ -n "$missing" ]; then
    if command -v luaotfload-tool > /dev/null; then
        luaotfload-tool --update > /dev/null 2>&1 \
            || warn "luaotfload-tool --update failed; the first lualatex run builds the font database"
    fi
fi
exit "$status"
