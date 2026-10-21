#!/usr/bin/env bash
# Container start (postStartCommand of every variant): runs each toolchain's post-start.sh, in the
# order of $DEVCONTAINER_TOOLCHAINS (the variant's toolchains from `initialize.sh <variant>
# <toolchain>...`, passed in by compose.core.yml). No-op without toolchains.
# A failing hook is reported but doesn't stop the others or the start.
set -uo pipefail

toolchains_dir="$(cd "$(dirname "$0")" && pwd)/toolchains"
for t in ${DEVCONTAINER_TOOLCHAINS:-}; do
    hook="$toolchains_dir/$t/post-start.sh"
    [ -f "$hook" ] || continue
    bash "$hook" || echo "post-start: WARNING $t/post-start.sh failed (exit $?)" >&2
done
exit 0
