#!/bin/bash
# Gracefully restart the gateway.
# Sends SIGTERM to the entrypoint (PID 1), which triggers cleanup + final sync.
# Docker's restart policy automatically restarts the container.
echo "🦞 Restarting gateway..."
kill -TERM 1
