#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_VM="$SCRIPT_DIR/../../vm"

echo "==> Building aidev:26 base from $WS_VM"
docker build -t aidev:26 -f "$WS_VM/Dockerfile" "$WS_VM"

echo "==> Building ymatch:26 from $SCRIPT_DIR"
docker build -t ymatch:26 -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"

echo "==> Done. Run: cd $SCRIPT_DIR && docker compose up -d"
