#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( dirname "$SCRIPT_DIR" )"

echo "Running Proto Generation via Docker Compose..."
# Use docker-compose to leverage caching and volumes
docker compose -f "$PROJECT_ROOT/docker-compose.proto.yml" run proto-gen \
  sh -c "protoc --dart_out=/workspace/frontend/lib/generated -I/workspace/proto /workspace/proto/models.proto && \
         cd /workspace/scripts/proto-gen-rs && cargo run"

echo "Done!"
