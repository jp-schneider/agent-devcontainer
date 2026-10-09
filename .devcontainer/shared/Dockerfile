# Base image is set by overlays (compose.gpu.yml sets the CUDA image).
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG IMAGE_NAME=claude-code-devcontainer
ARG IMAGE_VERSION=ubuntu24.04
# Toolchain under toolchains/<name>/ (set by the toolchain's compose overlay); "none" = core only
ARG TOOLCHAIN=none

LABEL org.opencontainers.image.title="$IMAGE_NAME" \
      org.opencontainers.image.version="$IMAGE_VERSION" \
      org.opencontainers.image.description="Hardened development container for coding agents, based on Ubuntu 24.04."

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    xz-utils \
    jq \
    vim \
    ripgrep \
    fd-find \
    htop \
    less \
    tree \
    wget \
    locales \
    unzip \
    nano \
    # Remove apt lists to reduce image size
    && rm -rf /var/lib/apt/lists/*

# Docker CLI, only useful with the docker-proxy overlay (which sets DOCKER_CLI=1)
ARG DOCKER_CLI=0
RUN if [[ "$DOCKER_CLI" == 1 ]]; then \
        apt-get update \
        && apt-get install -y --no-install-recommends docker-cli \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# Toolchain-specific system packages (toolchains/<name>/apt-packages.txt, one per line, # comments allowed)
COPY shared/toolchains/ /opt/devcontainer/toolchains/
RUN pkgs_file="/opt/devcontainer/toolchains/${TOOLCHAIN}/apt-packages.txt"; \
    if [[ -f "$pkgs_file" ]]; then \
        apt-get update \
        && sed 's/#.*//' "$pkgs_file" | xargs apt-get install -y --no-install-recommends \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# Project/variant system packages, merged by initialize.sh from .devcontainer/apt-packages.txt
# and .devcontainer/<variant>/apt-packages.txt; "pkg=version" pins are passed to apt as-is
COPY .generated/apt-packages.txt /opt/devcontainer/apt-packages.txt
RUN if grep -q '[^[:space:]]' /opt/devcontainer/apt-packages.txt; then \
        apt-get update \
        && xargs apt-get install -y --no-install-recommends < /opt/devcontainer/apt-packages.txt \
        && rm -rf /var/lib/apt/lists/*; \
    fi

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN set -eux; \
    existing_user="$(getent passwd "$USER_UID" | cut -d: -f1 || true)"; \
    existing_group="$(getent group "$USER_GID" | cut -d: -f1 || true)"; \
    if [[ -n "$existing_user" ]]; then \
        if [[ "$existing_user" != "$USERNAME" ]]; then \
            usermod -l "$USERNAME" "$existing_user"; \
        fi; \
        if [[ -n "$existing_group" && "$existing_group" != "$USERNAME" ]]; then \
            groupmod -n "$USERNAME" "$existing_group"; \
        fi; \
        usermod -d "/home/$USERNAME" -m "$USERNAME"; \
    else \
        if [[ -n "$existing_group" ]]; then \
            if [[ "$existing_group" != "$USERNAME" ]]; then \
                groupmod -n "$USERNAME" "$existing_group"; \
            fi; \
        else \
            groupadd --gid "$USER_GID" "$USERNAME"; \
        fi; \
        useradd --uid "$USER_UID" --gid "$USERNAME" -m "$USERNAME"; \
    fi

RUN mkdir -p /app \
    && chown -R $USER_UID:$USER_GID /app

USER $USERNAME

ENV SHELL=/bin/bash

# Security hardening: clear VS Code escape vectors injected into the container.
# Sourced from .bashrc before the interactive guard so it runs for non-interactive
# login shells (how Claude Code invokes bash).
RUN mkdir -p /home/vscode/.config \
    && { \
        echo 'unset VSCODE_IPC_HOOK_CLI'; \
        echo 'unset VSCODE_GIT_IPC_HANDLE GIT_ASKPASS VSCODE_GIT_ASKPASS_MAIN VSCODE_GIT_ASKPASS_NODE VSCODE_GIT_ASKPASS_EXTRA_ARGS'; \
        echo 'unset REMOTE_CONTAINERS_IPC REMOTE_CONTAINERS_SOCKETS REMOTE_CONTAINERS_DISPLAY_SOCK'; \
        echo 'unset WAYLAND_DISPLAY'; \
        echo 'export BROWSER='; \
        echo 'export SSH_AUTH_SOCK='; \
        echo 'export GPG_AGENT_INFO='; \
        } > /home/vscode/.config/security-harden.sh

RUN sed -i '1i source ~/.config/security-harden.sh 2>/dev/null || true' ~/.bashrc \
    && sed -i '2i export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc \
    && mkdir -p /home/vscode/.local/bin

# Claude Code, installed at build time (updates require an image rebuild)
RUN curl -fsSL https://claude.ai/install.sh | bash

RUN mkdir -p /home/vscode/.claude && chown -R vscode:vscode /home/vscode/.claude

# Toolchain user-level setup (toolchains/<name>/install.sh, runs as $USERNAME)
RUN install_sh="/opt/devcontainer/toolchains/${TOOLCHAIN}/install.sh"; \
    if [[ -f "$install_sh" ]]; then bash "$install_sh"; fi

WORKDIR /app

CMD ["sleep", "infinity"]
