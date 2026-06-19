# ymatch dev container

A Docker-in-Docker dev container for working on ymatch, layered on the local
`aidev:26` base image.

`aidev:26` already ships Docker-in-Docker, the `ubuntu` user (passwordless
sudo, in the `docker` group), and common CLI tools (`gh`, `task`, `make`,
`build-essential`, `git`, `ripgrep`, `jq`, `uv`). This image adds the
toolchains the project needs on top of that:

| Tool | Purpose |
|------|---------|
| Rust (stable + rustfmt/clippy/llvm-tools) | Axum/SQLx backend |
| Flutter (stable, web) | Flutter frontend |
| Node.js 22 + Claude Code CLI | AI coding assistant |
| Ollama | Local LLM runtime |

## Usage

```bash
# Build and start the container
docker compose -f vm/docker-compose.yml up -d --build

# Open a shell inside it
docker exec -it ymatch_dev bash

# From /home/ubuntu/ws/ymatch inside the container:
task test
```

The host workspace (`~/.ws`) is bind-mounted at `/home/ubuntu/ws`, so the
checkout lives at `/home/ubuntu/ws/ymatch` inside the container. A writable
copy of the host tmux config lives at `vm/storage/.tmux.conf` and is
bind-mounted at `/home/ubuntu/.tmux.conf` (edits persist on the host).

Because the container runs its own `dockerd`, the project's own
`docker-compose.yml` (PostgreSQL + pgAdmin) and `docker-compose.proto.yml` are
started *inside* the container. Their ports are forwarded to the host:

| Host port | Service |
|-----------|---------|
| 3000 | backend API |
| 8081 | Flutter web server |
| 5432 | PostgreSQL |
| 5050 | pgAdmin |

Ollama listens on `localhost:11434` **inside** the container only (not exposed
to the host). Start it / pull a model with `ollama serve` / `ollama pull`.

## Persistent storage

State that should survive container recreation is bind-mounted under
`vm/storage/` (gitignored):

| Host path | Container path | Contents |
|-----------|----------------|----------|
| `vm/storage/claude` | `/home/ubuntu/.claude` | Claude Code config / sessions |
| `vm/storage/gh` | `/home/ubuntu/.config/gh` | GitHub CLI auth / config |
| `vm/storage/ollama` | `/home/ubuntu/.ollama` | Ollama models |

Cargo and pub caches use named volumes (`cargo-cache`, `pub-cache`).

There is no SSH server — interact with the container via `docker exec`.