#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCLAW_REPO="git@github.com:openclaw/openclaw.git"
OPENCLAW_DIR="$SCRIPT_DIR/open-claw"

log() { echo "🦞 $1"; }
die() { echo "❌ $1" >&2; exit 1; }

# ─── Preflight checks ───────────────────────────────────────────────────────

command -v docker >/dev/null 2>&1 || die "Docker is not installed."
command -v git    >/dev/null 2>&1 || die "Git is not installed."
docker info >/dev/null 2>&1      || die "Docker daemon is not running."

# ─── Check .env ──────────────────────────────────────────────────────────────

if [ ! -f "$SCRIPT_DIR/.env" ]; then
    log "No .env found. Creating from template..."
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Created .env — fill in before continuing:"
    echo ""
    echo "    TELEGRAM_BOT_TOKEN=<token from @BotFather>"
    echo "    SETUP_PIN=<pick any pin>"
    echo ""
    echo "  Then run ./start.sh again."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi

# Validate .env
_env_val() { grep -m1 "^$1=" "$SCRIPT_DIR/.env" | cut -d= -f2-; }
TELEGRAM_BOT_TOKEN="$(_env_val TELEGRAM_BOT_TOKEN)"
SETUP_PIN="$(_env_val SETUP_PIN)"
[ -z "$TELEGRAM_BOT_TOKEN" ] && die "TELEGRAM_BOT_TOKEN is empty in .env"
[ -z "$SETUP_PIN" ]          && die "SETUP_PIN is empty in .env"

log "Config loaded"

# ─── Clone OpenClaw ──────────────────────────────────────────────────────────

if [ ! -d "$OPENCLAW_DIR" ]; then
    log "Cloning OpenClaw..."
    git clone --depth 1 "$OPENCLAW_REPO" "$OPENCLAW_DIR"
else
    log "OpenClaw repo found. Pulling latest..."
    (cd "$OPENCLAW_DIR" && git pull --ff-only 2>/dev/null || true)
fi

# ─── Build base image ───────────────────────────────────────────────────────

log "Building OpenClaw base image (this may take a few minutes)..."
(cd "$OPENCLAW_DIR" && docker build -t openclaw:local -f Dockerfile .)

# ─── Build Proton wrapper image ─────────────────────────────────────────────

log "Building OpenClaw + Proton image..."
(cd "$SCRIPT_DIR" && docker compose build)

# ─── Start ───────────────────────────────────────────────────────────────────

log "Starting OpenClaw..."
(cd "$SCRIPT_DIR" && docker compose up -d)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ OpenClaw is starting!"
echo ""
echo "  Dashboard:  http://127.0.0.1:18789/"
echo "  Logs:       docker compose logs -f"
echo "  Stop:       ./stop.sh"
echo ""
echo "  On first run, message the bot on Telegram:"
echo "    /setup YOUR_PIN email@proton.me your-proton-password"
echo ""
echo "  Secrets are then managed in Proton Pass → 'OpenClaw' vault"
echo "  State syncs to Proton Drive → '${SYNC_REMOTE_PATH:-OpenClaw}/' folder"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
