#!/bin/sh
set -e

# Start dockerd in the background
dockerd > /var/log/dockerd.log 2>&1 &

# Wait for Docker to start
echo "Waiting for Docker daemon to start..."
while ! docker info > /dev/null 2>&1; do
    sleep 1
done
echo "Docker daemon started."

# Ensure sshd requires the absolute path to run correctly in some containers
exec /usr/sbin/sshd -D
