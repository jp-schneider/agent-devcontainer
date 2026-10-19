# Headless LM Studio (llmster) for compose.lmstudio-sidecar.yml. No official image exists.
#
# Mirrors what https://lmstudio.ai/install.sh does (inspected at llmster 0.0.25-1), minus two
# things: the script picks the CUDA bundle only if nvidia-smi works *at install time*, which it
# doesn't during `docker build`, so we fetch the +cuda12 bundle explicitly; and it trusts a checksum
# from the same host, so we pin it here. To update: take APP_VERSION from the current install.sh
# and the hash from https://llmster.lmstudio.ai/download/<version>-linux-x64.full%2Bcuda12.sha512
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl libatomic1 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Same UID/GID as the host user, so models downloaded into the bind-mounted dir are the user's.
# -o: the IDs may collide with an image user/group (ubuntu 1000, or GID 20 on macOS hosts)
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN userdel -r ubuntu 2> /dev/null; \
    groupadd -o --gid "$USER_GID" lmstudio \
    && useradd -o --uid "$USER_UID" --gid "$USER_GID" -m lmstudio
USER lmstudio
WORKDIR /home/lmstudio

ARG LLMSTER_VERSION=0.0.25-1
ARG LLMSTER_SHA512=179e05cee62c1e1f61f1c6480179b1e21df63af64ffa3a949a94f026afc4552d7a36db7208345e65f21f040d864c1603bf6cd1c0292e4751d696bee5679db007
RUN set -eux; \
    tmp="$(mktemp -d)"; \
    curl -fsSL -o "$tmp/llmster.tar.gz" \
        "https://llmster.lmstudio.ai/download/${LLMSTER_VERSION}-linux-x64.full%2Bcuda12.tar.gz"; \
    echo "${LLMSTER_SHA512}  $tmp/llmster.tar.gz" | sha512sum -c -; \
    tar xf "$tmp/llmster.tar.gz" -C "$tmp"; \
    LMS_BOOTSTRAP_INSTALL_SH=1 "$tmp/llmster" bootstrap; \
    rm -rf "$tmp"; \
    mkdir -p /home/lmstudio/.lmstudio/models

ENV PATH=/home/lmstudio/.lmstudio/bin:$PATH
EXPOSE 1234
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s \
    CMD curl -fsS http://localhost:1234/v1/models > /dev/null || exit 1

# `lms server start` returns once the daemon serves; sleep keeps the container up (the
# healthcheck reports a dead daemon). Inside the container only, so binding all interfaces is
# fine: the compose service publishes no port, only the dev network reaches it.
CMD ["bash", "-c", "lms daemon up && lms server start --bind 0.0.0.0 --port 1234 && exec sleep infinity"]
