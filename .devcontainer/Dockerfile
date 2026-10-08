FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04

ARG IMAGE_NAME=devcontainer-python-gpu
ARG IMAGE_VERSION=cuda-13.0.3-cudnn-ubuntu24.04

LABEL org.opencontainers.image.title="$IMAGE_NAME" \
      org.opencontainers.image.version="$IMAGE_VERSION" \
      org.opencontainers.image.description="Development container image for Python projects with GPU support, based on Ubuntu 24.04 and CUDA 13.0.3 with cuDNN."

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
    docker-cli \
    wget \
    locales \
    unzip \
    nano \
    # OpenCV
    ffmpeg libsm6 libxext6 \
    # Python Build Dependencies
    make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev curl git \
    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev libzstd-dev \
    # Dependencies for tinycudann
    cmake gcc build-essential \
    # Remove apt lists to reduce image size
    && rm -rf /var/lib/apt/lists/*

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
    && mkdir -p /home/vscode/.local/bin /home/vscode/.virtualenvs /home/vscode/.local/share/uv/python

RUN curl -LsSf https://astral.sh/uv/install.sh | sh && export PATH="$HOME/.local/bin:$PATH" && uv tool install ruff && uv tool install ty

RUN mkdir -p /home/vscode/.claude && chown -R vscode:vscode /home/vscode/.claude

WORKDIR /app

CMD ["sleep", "infinity"]
