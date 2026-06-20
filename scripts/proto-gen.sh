#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( dirname "$SCRIPT_DIR" )"

# The proto-gen container runs as root (the default) so it can read the Dart
# protoc plugin in /root/.pub-cache and write to the shared rust_cargo_cache
# volume. That also means protoc/cargo write their output into the workspace
# bind-mount as root, leaving root-owned files in the repo (which breaks
# worktree cleanup — see #272). We can't simply run as the host user because
# the pub-cache and cargo volume are root-owned, so instead we chown the
# written outputs back to the host user at the end of the run.
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

echo "Running Proto Generation via Docker Compose..."
# Use docker-compose to leverage caching and volumes. --rm drops the one-shot
# container once the command finishes.
docker compose -f "$PROJECT_ROOT/docker-compose.proto.yml" run --rm \
  -e HOST_UID="$HOST_UID" -e HOST_GID="$HOST_GID" \
  proto-gen \
  sh -c "protoc --dart_out=/workspace/frontend/lib/generated -I/workspace/proto /workspace/proto/models.proto && \
         cd /workspace/scripts/proto-gen-rs && cargo run && \
         chown -R \"\$HOST_UID:\$HOST_GID\" \
           /workspace/scripts/proto-gen-rs/target \
           /workspace/frontend/lib/generated \
           /workspace/backend/src/generated"

echo "Done!"