#!/bin/bash
set -e

# Start Docker daemon in the background
dockerd > /var/log/dockerd.log 2>&1 &

# Wait until the Docker socket is ready
echo "Waiting for Docker daemon to start..."
timeout 30 sh -c 'until docker info > /dev/null 2>&1; do sleep 1; done'
echo "Docker daemon is ready."

# Hand off to sshd (keeps container alive)
exec /usr/sbin/sshd -D
