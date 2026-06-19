# Dev container for ymatch, layered on top of the local `aidev:26` image.
#
# `aidev:26` already provides: Docker-in-Docker (dockerd via its entrypoint),
# the `ubuntu` user (uid 1000, passwordless sudo, in the docker group), plus
# `gh`, `task`, `make`, `build-essential`, `git`, `ripgrep`, `jq`, and `uv`.
#
# This image adds what the ymatch toolchain needs on top of that:
#   - Node.js 22 + Claude Code CLI
#   - Ollama (local LLM runtime)
#   - Rust (stable + rustfmt/clippy/llvm-tools) for the Axum/SQLx backend
#   - Flutter (stable channel, web artifacts) for the frontend
#
# Build:  docker compose -f vm/docker-compose.yml build
# Run:    docker compose -f vm/docker-compose.yml up -d
# Shell:  docker exec -it ymatch_dev bash

FROM aidev:26

# ── System tooling (root) ────────────────────────────────────────────────────
USER root

# Node.js 22 — required to run the Claude Code CLI. zstd is needed by the
# Ollama installer's extraction step. locales backs the en_US.UTF-8 locale.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs zstd locales && rm -rf /var/lib/apt/lists/*

# en_US.UTF-8 locale (falls back to C.UTF-8 if unavailable).
RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en



# ── User toolchain (ubuntu) ──────────────────────────────────────────────────
USER ubuntu

# Claude Code CLI (config persists via the ./storage/claude bind mount).
RUN curl -fsSL https://claude.ai/install.sh | bash

# Ollama — local LLM runtime (models persist via the ./storage/ollama mount).
RUN curl -fsSL https://ollama.com/install.sh | sh

# Pre-create the config dirs that aidev's entrypoint chowns at startup, so the
# container boots even when those bind mounts are absent.
RUN mkdir -p \
        /home/ubuntu/.claude \
        /home/ubuntu/.config/opencode \
        /home/ubuntu/.config/gh \
        /home/ubuntu/.local/share/opencode

# ── Rust toolchain ───────────────────────────────────────────────────────────
# backend/Cargo.toml requires rust-version 1.85; a recent stable satisfies it.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --component rustfmt,clippy,llvm-tools-preview
ENV PATH="/home/ubuntu/.cargo/bin:${PATH}"

# cargo-llvm-cov backs `task backend:coverage`.
RUN cargo install cargo-llvm-cov

# ── Flutter SDK ──────────────────────────────────────────────────────────────
RUN git clone --depth 1 -b stable https://github.com/flutter/flutter.git \
        /home/ubuntu/flutter
ENV PATH="/home/ubuntu/flutter/bin:${PATH}"
RUN flutter config --no-analytics && flutter precache --web

# Make Rust + Flutter discoverable in interactive shells (compose `docker exec`).
RUN echo 'export PATH="/home/ubuntu/.cargo/bin:/home/ubuntu/flutter/bin:${PATH}"' \
        >> /home/ubuntu/.bashrc

WORKDIR /home/ubuntu/ws
