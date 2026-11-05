#!/usr/bin/env bats
# latex toolchain: post-start.sh (TeX Live install into the shared volume: signature check against
# the pinned key, checksum, release year, interrupted installs, offline, lock; package lists),
# init-host.sh (volume), install.sh (mount point, PATH snippet), the package lists.
# post-start.sh runs only in the container (Linux, flock); fakes stand in for curl, gpg, install-tl
# and tlmgr, plus one test with real gpg (skipped without it).

load helpers

PIN=C78B82D8C79512F79CC0D7C80D5E5D9106BAB6BC
FAKE_PIN=AAAA0000BBBB1111CCCC2222DDDD3333EEEE4444
OTHER=FFFF9999FFFF9999FFFF9999FFFF9999FFFF9999

setup() {
    setup_workdir
    fake_docker
    ROOT="$WORK/texlive"
    mkdir -p "$ROOT" "$WORK/ctan"
    # The toolchain, with the pinned fingerprint replaced by the fake key's
    cp -R "$SHARED/toolchains/latex" "$WORK/latex"
    sed -i "s/^TEXLIVE_GPG_FINGERPRINT=.*/TEXLIVE_GPG_FINGERPRINT=$FAKE_PIN/" "$WORK/latex/post-start.sh"
    export TEXLIVE_ROOT="$ROOT" TEXLIVE_YEAR=2026 TEXLIVE_REPOSITORY=https://ctan.test/tlnet/
    export TEX_PACKAGES_PROJECT="$WORK/project-tex.txt"
    echo 'siunitx # units' > "$TEX_PACKAGES_PROJECT"
    fake_curl
    fake_gpg
    # post-start.sh writes to ~/.config (fontconfig link): never the real home
    export HOME="$WORK/home"
    mkdir -p "$HOME"
    printf '#!/bin/sh\necho "$*" >> "%s/fc-cache.log"\n' "$WORK" > "$WORK/bin/fc-cache"
    chmod +x "$WORK/bin/fc-cache"
}

teardown() {
    teardown_workdir
}

needs_linux() {
    command -v flock > /dev/null || skip "post-start.sh needs flock (Linux, container only)"
    tar --version 2> /dev/null | grep -q GNU || skip "post-start.sh needs GNU tar"
}

# fake_curl: `curl … -o <out> <url>` copies $WORK/ctan/<basename url>; FAKE_OFFLINE=1 fails. Like
# mirror.ctan.org, https://ctan.test/ redirects to a mirror (https://mirror1.test/), which
# `-w '%{url_effective}'` prints.
fake_curl() {
    cat > "$WORK/bin/curl" << EOF
#!/usr/bin/env bash
out=""; url=""; w=""
while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2 ;; -w) w=1; shift 2 ;; --retry) shift 2 ;; -*) shift ;; *) url="\$1"; shift ;; esac; done
echo "\$url" >> "$WORK/curl.log"
[ -z "\${FAKE_OFFLINE:-}" ] || exit 6
cp "$WORK/ctan/\${url##*/}" "\$out" 2> /dev/null || exit 22
[ -z "\$w" ] || printf '%s' "\${url/ctan.test/mirror1.test}"
EOF
    chmod +x "$WORK/bin/curl"
}

# fake_gpg: a "key" is a file holding its fingerprint, a "signature" is "sig <fpr> <sha512 of data>".
# --verify prints VALIDSIG with the signer as primary key if that key was imported and the hash matches.
fake_gpg() {
    mkdir -p "$WORK/fakegpg"
    cat > "$WORK/fakegpg/gpg" << 'EOF'
#!/usr/bin/env bash
case " $* " in
    *" --import "*) for a; do f="$a"; done; cat "$f" >> "$GNUPGHOME/keys" ;;
    *" --verify "*)
        n=$#; asc="${*:n-1:1}"; data="${*:n:1}"
        read -r _ fpr sum < "$asc"
        if grep -qx "$fpr" "$GNUPGHOME/keys" 2> /dev/null && [ "$sum" = "$(sha512sum < "$data" | cut -d' ' -f1)" ]; then
            echo "[GNUPG:] GOODSIG X"
            echo "[GNUPG:] VALIDSIG 1111222233334444555566667777888899990000 2026-03-01 0 4 0 22 10 00 $fpr"
        else
            echo "[GNUPG:] BADSIG X"; exit 1
        fi ;;
esac
EOF
    chmod +x "$WORK/fakegpg/gpg"
    export PATH="$WORK/fakegpg:$PATH"
}

# make_ctan [<bundled key> [<signer> [<release year>]]]: an installer in $WORK/ctan. Its install-tl
# installs a fake TeX Live (tlmgr, luaotfload-tool) at the profile's TEXDIR; logs go to $WORK.
make_ctan() {
    local key="${1:-$FAKE_PIN}" signer="${2:-$FAKE_PIN}" release="${3:-2026}"
    local src="$WORK/src/install-tl-20260301"
    rm -rf "$WORK/src"
    mkdir -p "$src/tlpkg/gpg"
    echo "$key" > "$src/tlpkg/gpg/pubring.gpg"
    echo "TeX Live (https://tug.org/texlive) version $release" > "$src/release-texlive.txt"
    cat > "$src/install-tl" << EOF
#!/usr/bin/env bash
echo "\$*" >> "$WORK/install-tl.log"
profile=""; while [ \$# -gt 0 ]; do [ "\$1" = -profile ] && profile="\$2"; shift; done
cp "\$profile" "$WORK/profile.used"
texdir="\$(sed -n 's/^TEXDIR //p' "\$profile")"
bin="\$texdir/bin/x86_64-linux"
mkdir -p "\$bin"
printf '%s\n' scheme-basic collection-basic collection-latex > "\$texdir/installed.txt"
mkdir -p "\$texdir/texmf-var/fonts/conf"
echo '<fontconfig/>' > "\$texdir/texmf-var/fonts/conf/texlive-fontconfig.conf"
cat > "\$bin/tlmgr" << 'TL'
#!/usr/bin/env bash
db="\$(dirname "\$0")/../../installed.txt"
r=""; [ "\$1" = --repository ] && { r="[\$2] "; shift 2; }
case "\$1" in
    info) cat "\$db" ;;
    update|option) echo "\$r\$*" >> "$WORK/tlmgr.log" ;;
    install)
        shift; echo "\${r}install \$*" >> "$WORK/tlmgr.log"
        [ -z "\${FAKE_TLMGR_FAIL:-}" ] || exit 1
        n=\$(cat "$WORK/tlmgr.fails" 2> /dev/null || echo 0)
        if [ "\$n" -lt "\${FAKE_TLMGR_FAIL_TIMES:-0}" ]; then echo \$((n + 1)) > "$WORK/tlmgr.fails"; exit 1; fi
        printf '%s\n' "\$@" >> "\$db" ;;
esac
TL
printf '#!/bin/sh\necho "\$*" >> "$WORK/luaotfload.log"\n' > "\$bin/luaotfload-tool"
chmod +x "\$bin/tlmgr" "\$bin/luaotfload-tool"
exit "\${FAKE_INSTALL_FAIL:-0}"
EOF
    chmod +x "$src/install-tl"
    tar -czf "$WORK/ctan/install-tl-unx.tar.gz" -C "$WORK/src" install-tl-20260301
    (cd "$WORK/ctan" && sha512sum install-tl-unx.tar.gz > install-tl-unx.tar.gz.sha512)
    echo "sig $signer $(sha512sum < "$WORK/ctan/install-tl-unx.tar.gz.sha512" | cut -d' ' -f1)" \
        > "$WORK/ctan/install-tl-unx.tar.gz.sha512.asc"
}

start() {
    run "$BASH_UNDER_TEST" "$WORK/latex/post-start.sh"
}

installed() {
    grep -qx "$1" "$ROOT/2026/installed.txt"
}

@test "first start: signed installer verified, TeX Live installed, then the missing packages of both lists" {
    needs_linux
    make_ctan
    start
    [ "$status" -eq 0 ]
    [ -f "$ROOT/2026/.devcontainer-installed" ]
    grep -qx "selected_scheme scheme-basic" "$WORK/profile.used"
    grep -qx "TEXDIR $ROOT/2026" "$WORK/profile.used"
    grep -qx "TEXMFSYSVAR $ROOT/2026/texmf-var" "$WORK/profile.used"
    grep -qx "tlpdbopt_install_docfiles 0" "$WORK/profile.used"
    # tlmgr updates itself, then gets one install call: toolchain + project list, minus scheme-basic's
    [ "$(grep -v '^option' "$WORK/tlmgr.log" | sed -n 1p)" = "[https://mirror1.test/tlnet] update --self" ]
    [ "$(grep -c '^\[https://mirror1.test/tlnet\] install' "$WORK/tlmgr.log")" = 1 ]
    for p in collection-latexextra latexmk biber latexindent siunitx; do installed "$p"; done
    not_grep 'install .*collection-latex\b' "$WORK/tlmgr.log"
    grep -qx -- '--update' "$WORK/luaotfload.log"
}

@test "one mirror: the redirector is resolved once, for all downloads and install-tl; tlmgr goes back to it" {
    needs_linux
    make_ctan
    start
    [ "$status" -eq 0 ]
    [ "$(tr '\n' ' ' < "$WORK/curl.log")" = "https://ctan.test/tlnet/install-tl-unx.tar.gz https://mirror1.test/tlnet/install-tl-unx.tar.gz.sha512 https://mirror1.test/tlnet/install-tl-unx.tar.gz.sha512.asc " ]
    grep -qx -- "-profile .*/texlive.profile -repository https://mirror1.test/tlnet" "$WORK/install-tl.log"
    [ "$(sed -n 1p "$WORK/tlmgr.log")" = "option repository https://ctan.test/tlnet" ]
    output_has "installing TeX Live 2026 from https://mirror1.test/tlnet"
}

@test "later starts: no download; nothing missing, no tlmgr; a new project package installed alone" {
    needs_linux
    make_ctan
    start
    rm -f "$WORK/curl.log" "$WORK/tlmgr.log" "$WORK/luaotfload.log"
    start
    [ "$status" -eq 0 ]
    [ ! -e "$WORK/curl.log" ]
    [ ! -e "$WORK/tlmgr.log" ]
    [ ! -e "$WORK/luaotfload.log" ]
    echo 'siunitx collection-langgerman' > "$TEX_PACKAGES_PROJECT"
    start
    [ "$status" -eq 0 ]
    # From the recorded install mirror
    [ "$(grep 'install' "$WORK/tlmgr.log")" = "[https://mirror1.test/tlnet] install collection-langgerman" ]
}

@test "an interrupted install (no stamp) is removed and redone" {
    needs_linux
    make_ctan
    mkdir -p "$ROOT/2026/half"
    start
    [ "$status" -eq 0 ]
    output_has "removing an incomplete TeX Live 2026 install"
    [ ! -e "$ROOT/2026/half" ]
    [ -f "$ROOT/2026/.devcontainer-installed" ]
}

@test "installer signed by another key (bundled with it): not run, volume left clean" {
    needs_linux
    make_ctan "$OTHER" "$OTHER"
    start
    [ "$status" -ne 0 ]
    output_has "signature not by the pinned key $FAKE_PIN"
    [ ! -e "$WORK/install-tl.log" ]
    [ ! -e "$ROOT/2026" ]
}

@test "tampered installer (doesn't match the signed checksum): not run" {
    needs_linux
    make_ctan
    # Re-packed with a changed install-tl; checksum and signature are the original ones
    echo 'echo pwned' >> "$WORK/src/install-tl-20260301/install-tl"
    tar -czf "$WORK/ctan/install-tl-unx.tar.gz" -C "$WORK/src" install-tl-20260301
    start
    [ "$status" -ne 0 ]
    output_has "installer doesn't match its signed checksum"
    [ ! -e "$WORK/install-tl.log" ]
}

@test "repository has a newer release: not installed, points at updating the template and the archive" {
    needs_linux
    make_ctan "$FAKE_PIN" "$FAKE_PIN" 2027
    start
    [ "$status" -ne 0 ]
    output_has "the repository has 2027, not TeX Live 2026"
    output_has "historic/systems/texlive/2026/tlnet-final"
    [ ! -e "$ROOT/2026" ]
}

@test "offline: a warning, nothing left behind; installed on the next start" {
    needs_linux
    make_ctan
    FAKE_OFFLINE=1 start
    [ "$status" -ne 0 ]
    output_has "could not download"
    [ ! -e "$ROOT/2026" ]
    start
    [ "$status" -eq 0 ]
    [ -f "$ROOT/2026/.devcontainer-installed" ]
}

@test "install-tl fails: log tail shown, the partial tree removed" {
    needs_linux
    make_ctan
    FAKE_INSTALL_FAIL=3 start
    [ "$status" -ne 0 ]
    output_has "install-tl failed (exit 3)"
    [ ! -e "$ROOT/2026" ]
}

@test "tlmgr install fails: warning with the release hint; TeX Live stays, retried next start" {
    needs_linux
    make_ctan
    FAKE_TLMGR_FAIL=1 start
    [ "$status" -ne 0 ]
    output_has "If TeX Live 2027 is out"
    [ -f "$ROOT/2026/.devcontainer-installed" ]
    rm -f "$WORK/tlmgr.log"
    start
    [ "$status" -eq 0 ]
    grep -q 'install .*siunitx' "$WORK/tlmgr.log"
}

@test "later starts: the recorded install mirror first, then up to 3 tries via the redirector" {
    needs_linux
    make_ctan
    start
    [ "$(cat "$ROOT/2026/.devcontainer-mirror")" = "https://mirror1.test/tlnet" ]
    echo 'siunitx collection-langgerman' > "$TEX_PACKAGES_PROJECT"
    rm -f "$WORK/tlmgr.log"
    FAKE_TLMGR_FAIL_TIMES=2 start
    [ "$status" -eq 0 ]
    [ "$(grep install "$WORK/tlmgr.log" | tr '\n' '|')" \
        = "[https://mirror1.test/tlnet] install collection-langgerman|install collection-langgerman|install collection-langgerman|" ]
    output_has "tlmgr failed with the install mirror https://mirror1.test/tlnet, trying the configured repository"
    output_has "retrying with another mirror"
    installed collection-langgerman
    echo 'siunitx lipsum' > "$TEX_PACKAGES_PROJECT"
    rm -f "$WORK/tlmgr.log" "$WORK/tlmgr.fails"
    FAKE_TLMGR_FAIL_TIMES=9 start
    [ "$status" -ne 0 ]
    [ "$(grep -c 'install lipsum' "$WORK/tlmgr.log")" = 4 ]
    output_has "mirrors still behind this install"
}

@test "a volume without the recorded mirror (installed by an older version) goes via the redirector" {
    needs_linux
    make_ctan
    start
    rm "$ROOT/2026/.devcontainer-mirror"
    echo 'siunitx lipsum' > "$TEX_PACKAGES_PROJECT"
    rm -f "$WORK/tlmgr.log"
    start
    [ "$status" -eq 0 ]
    [ "$(grep install "$WORK/tlmgr.log")" = "install lipsum" ]
}

@test "first start: no retry via another mirror, the install mirror is the right one" {
    needs_linux
    make_ctan
    FAKE_TLMGR_FAIL_TIMES=1 start
    [ "$status" -ne 0 ]
    [ "$(grep -c 'install' "$WORK/tlmgr.log")" = 1 ]
    [ -f "$ROOT/2026/.devcontainer-installed" ]
}

@test "missing packages are computed in C collation, whatever the locale (en_US sorts cmap before cm-super)" {
    needs_linux
    locale -a 2> /dev/null | grep -qix 'en_US.utf-\?8' || skip "no en_US.UTF-8 locale"
    make_ctan
    start
    # cmap installed, cm-super not: comm in en_US collation would report cmap missing as well
    grep -vx cm-super "$ROOT/2026/installed.txt" > "$WORK/db"
    echo cmap >> "$WORK/db"
    cp "$WORK/db" "$ROOT/2026/installed.txt"
    echo 'cm-super cmap' > "$TEX_PACKAGES_PROJECT"
    rm -f "$WORK/tlmgr.log"
    LC_ALL=en_US.UTF-8 start
    [ "$status" -eq 0 ]
    [ "$(grep install "$WORK/tlmgr.log")" = "[https://mirror1.test/tlnet] install cm-super" ]
}

@test "fontconfig: TeX Live's fonts linked in for XeTeX; cache refreshed only when the link is new or packages came in" {
    needs_linux
    make_ctan
    start
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.config/fontconfig/conf.d/09-texlive.conf")" = "$ROOT/2026/texmf-var/fonts/conf/texlive-fontconfig.conf" ]
    grep -qx -- '-f' "$WORK/fc-cache.log"
    rm -f "$WORK/fc-cache.log"
    start
    [ ! -e "$WORK/fc-cache.log" ]
    # A rebuild loses ~/.config
    rm -rf "$HOME/.config"
    start
    [ -L "$HOME/.config/fontconfig/conf.d/09-texlive.conf" ]
    grep -qx -- '-f' "$WORK/fc-cache.log"
}

@test "list entries that aren't package names never reach tlmgr" {
    needs_linux
    make_ctan
    printf 'siunitx --repository=evil -x ../up a;b\n' > "$TEX_PACKAGES_PROJECT"
    start
    [ "$status" -eq 0 ]
    output_has "skipping '--repository=evil'"
    output_has "skipping '../up'"
    output_has "skipping 'a;b'"
    not_grep -e 'evil' -e '\.\./up' -e 'a;b' -e ' -x' "$WORK/tlmgr.log"
    installed siunitx
}

@test "waits while another container holds the volume's lock" {
    needs_linux
    make_ctan
    flock "$ROOT/.lock" sleep 1 &
    for _ in $(seq 50); do flock -n "$ROOT/.lock" true || break; sleep 0.02; done
    start
    wait
    [ "$status" -eq 0 ]
    output_has "another container is installing into the TeX Live volume, waiting"
}

@test "fails early without a year or a writable volume" {
    needs_linux
    TEXLIVE_YEAR="" start
    [ "$status" -ne 0 ]
    output_has "TEXLIVE_YEAR is ''"
    TEXLIVE_ROOT="$WORK/missing" start
    [ "$status" -ne 0 ]
    output_has "is missing or not writable"
}

@test "real gpg: only a signature by the pinned key passes, a bundled look-alike key doesn't" {
    needs_linux
    PATH="${PATH//$WORK\/fakegpg:/}"
    command -v gpg > /dev/null || skip "gpg not installed"
    export GNUPGHOME="$WORK/signer"
    mkdir -m 700 "$GNUPGHOME"
    gpg --batch --quiet --passphrase '' --quick-gen-key 'Pinned <pinned@test>' ed25519 sign never
    gpg --batch --quiet --passphrase '' --quick-gen-key 'Other <other@test>' ed25519 sign never
    fpr() { gpg --with-colons --list-keys "$1" | awk -F: '/^fpr/ { print $10; exit }'; }
    pinned="$(fpr pinned@test)"
    other="$(fpr other@test)"
    sed -i "s/^TEXLIVE_GPG_FINGERPRINT=.*/TEXLIVE_GPG_FINGERPRINT=$pinned/" "$WORK/latex/post-start.sh"
    # sign_ctan <key uid>: bundle that key's public key, sign the checksum with it
    sign_ctan() {
        make_ctan
        # Binary keyring, as TeX Live ships it
        gpg --export "$1" > "$WORK/src/install-tl-20260301/tlpkg/gpg/pubring.gpg"
        tar -czf "$WORK/ctan/install-tl-unx.tar.gz" -C "$WORK/src" install-tl-20260301
        (cd "$WORK/ctan" && sha512sum install-tl-unx.tar.gz > install-tl-unx.tar.gz.sha512)
        gpg --batch --yes --quiet --local-user "$1" --armor --detach-sign \
            -o "$WORK/ctan/install-tl-unx.tar.gz.sha512.asc" "$WORK/ctan/install-tl-unx.tar.gz.sha512"
    }
    sign_ctan other@test
    unset GNUPGHOME
    start
    [ "$status" -ne 0 ]
    output_has "signature not by the pinned key $pinned"
    [ ! -e "$ROOT/2026" ]
    export GNUPGHOME="$WORK/signer"
    sign_ctan pinned@test
    unset GNUPGHOME
    start
    [ "$status" -eq 0 ]
    [ -f "$ROOT/2026/.devcontainer-installed" ]
    [ -n "$other" ]
}

@test "the shipped script pins TeX Live's key" {
    grep -qx "TEXLIVE_GPG_FINGERPRINT=$PIN" "$SHARED/toolchains/latex/post-start.sh"
}

@test "init-host: creates the shared volume with the resource prefix" {
    printf 'RESOURCE_PREFIX=my-prefix\n' > "$WORK/env"
    run "$BASH_UNDER_TEST" "$SHARED/toolchains/latex/init-host.sh" "$WORK/env"
    [ "$status" -eq 0 ]
    grep -qx 'docker volume create my-prefix-latex-texlive' "$WORK/docker.log"
}

@test "install.sh: volume mount point, and the PATH snippet adds the release's bin dir once" {
    export HOME="$WORK/home"
    mkdir -p "$HOME"
    printf '# 1\n# 2\n# 3\n# 4\n' > "$HOME/.bashrc"
    run "$BASH_UNDER_TEST" "$SHARED/toolchains/latex/install.sh"
    [ "$status" -eq 0 ]
    [ -d "$HOME/.local/texlive" ]
    [ "$(sed -n 3p "$HOME/.bashrc")" = 'source ~/.config/latex-toolchain.sh 2>/dev/null || true' ]
    mkdir -p "$ROOT/2026/bin/x86_64-linux"
    run "$BASH_UNDER_TEST" -c 'PATH=/usr/bin; . "$HOME/.config/latex-toolchain.sh"; . "$HOME/.config/latex-toolchain.sh"; echo "$PATH"'
    [ "$output" = "$ROOT/2026/bin/x86_64-linux:/usr/bin" ]
    TEXLIVE_YEAR="" run "$BASH_UNDER_TEST" -c 'PATH=/usr/bin; . "$HOME/.config/latex-toolchain.sh"; echo "$PATH"'
    [ "$output" = "/usr/bin" ]
}

@test "package lists: names only; the toolchain's has the editor tools, not scheme-full; the project's ships empty" {
    names() { sed 's/#.*//' "$1" | tr -s ' \t' '\n\n' | grep .; }
    names "$SHARED/toolchains/latex/tex-packages.txt" | while read -r p; do
        [[ "$p" =~ ^[a-z0-9][a-z0-9.-]+$ ]] || { echo "not a package name: $p" >&2; exit 1; }
    done
    for p in collection-latexextra latexmk biber chktex latexindent collection-luatex; do
        names "$SHARED/toolchains/latex/tex-packages.txt" | grep -qx "$p"
    done
    ! names "$SHARED/toolchains/latex/tex-packages.txt" | grep -q '^scheme-'
    [ -z "$(names "$REPO_ROOT/.devcontainer/tex-packages.txt")" ]
    # apt: what upstream TeX Live needs from the system, no Debian TeX Live next to it
    names "$SHARED/toolchains/latex/apt-packages.txt" | grep -qx gnupg
    ! names "$SHARED/toolchains/latex/apt-packages.txt" | grep -q '^texlive'
}
