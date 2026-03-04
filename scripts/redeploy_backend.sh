#!/bin/bash
set -e

echo "Stopping existing Backend processes safely..."
kill $(cat backend/backend.pid 2>/dev/null) 2>/dev/null || true
kill $(ps aux | grep 'target/debug/backend' | grep -v grep | awk '{print $2}') 2>/dev/null || true
kill $(ps aux | grep 'cargo run' | grep -v grep | awk '{print $2}') 2>/dev/null || true

# Wait for port 3000 to clear
sleep 2

echo "Building and starting Backend Server in background..."
cd backend
export DATABASE_URL="postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch"

# Clean build artifacts if needed, though cargo check/run is usually robust.
cargo check > /dev/null 2>&1

nohup cargo run --bin backend > backend.log 2>&1 &
echo $! > backend.pid

echo "Backend re-deployment started. Check backend/backend.log for progress."
exit 0