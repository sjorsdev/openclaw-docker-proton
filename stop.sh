#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🦞 Stopping OpenClaw (waiting for final Drive sync)..."
docker compose down --timeout 30
echo "✅ Stopped."
