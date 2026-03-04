#!/bin/bash
set -e

echo "Stopping existing Flutter Web processes safely..."
kill $(cat frontend/flutter.pid 2>/dev/null) 2>/dev/null || true
kill $(ps aux | grep 'flutter_tools' | grep -v grep | awk '{print $2}') 2>/dev/null || true
kill $(ps aux | grep 'dart' | grep -v grep | awk '{print $2}') 2>/dev/null || true

# Wait for ports to actually clear
sleep 2

echo "Ensuring clean build environment..."
cd frontend
export PATH="$HOME/development/flutter/bin:$PATH"

# Sometimes the pub cache or build directory causes stale code to be served on the web.
# Running clean forces the next run to recompile from scratch.
flutter clean > /dev/null 2>&1
flutter pub get > /dev/null 2>&1

echo "Starting Flutter Web Server in background..."
nohup flutter run -d web-server --web-port 8081 > flutter.log 2>&1 &
echo $! > flutter.pid

echo "Frontend re-deployment started. Check frontend/flutter.log for progress."
exit 0