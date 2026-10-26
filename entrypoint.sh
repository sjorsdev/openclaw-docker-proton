#!/bin/bash
set -euo pipefail

log() { echo "🦞 $1"; }
warn() { echo "⚠️  $1"; }
die() { echo "❌ $1" >&2; exit 1; }

# ─── Validate required env vars ──────────────────────────────────────────────

[ -z "${TELEGRAM_BOT_TOKEN:-}" ] && die "TELEGRAM_BOT_TOKEN not set"

SYNC_INTERVAL="${SYNC_INTERVAL:-60}"
OPENCLAW_HOME="${HOME}/.openclaw"
SYNC_REMOTE_PATH="${SYNC_REMOTE_PATH:-OpenClaw}"
EXCLUDE_FILE="/opt/openclaw-proton/rclone-exclude.txt"

# Persist pass-cli and rclone state in the mounted volume
export XDG_DATA_HOME="$OPENCLAW_HOME/.local/share"
export XDG_CONFIG_HOME="$OPENCLAW_HOME/.config"
export RCLONE_CONFIG="$OPENCLAW_HOME/.rclone.conf"
export PROTON_PASS_KEY_PROVIDER=fs
export PLAYWRIGHT_BROWSERS_PATH="$OPENCLAW_HOME/.browsers"

mkdir -p "$OPENCLAW_HOME/workspace" "$OPENCLAW_HOME/local" "$OPENCLAW_HOME/.browsers" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"

# Helper: generate TOTP for rclone 2FA if Proton Bot item has TOTP configured
rclone_2fa() {
    local totp
    totp=$(pass-cli item totp "pass://OpenClaw/Proton Bot" 2>/dev/null | head -1 | awk '{print $2}') || true
    if [ -n "$totp" ]; then
        rclone "$@" --protondrive-2fa="$totp"
    else
        rclone "$@"
    fi
}

# ─── 1. Generate encryption key if needed ────────────────────────────────────

KEY_FILE="$OPENCLAW_HOME/.encryption-key"
if [ -z "${PROTON_PASS_ENCRYPTION_KEY:-}" ]; then
    if [ -f "$KEY_FILE" ]; then
        export PROTON_PASS_ENCRYPTION_KEY=$(cat "$KEY_FILE")
    else
        export PROTON_PASS_ENCRYPTION_KEY=$(openssl rand -hex 32)
        echo "$PROTON_PASS_ENCRYPTION_KEY" > "$KEY_FILE"
        chmod 600 "$KEY_FILE"
        log "Generated encryption key"
    fi
fi

# ─── 2. Login to Proton Pass (via Telegram if needed) ───────────────────────

if pass-cli vault list &>/dev/null; then
    log "Proton Pass session active ✓"
else
    log "Proton Pass not configured — starting Telegram setup..."
    export OPENCLAW_HOME RCLONE_CONFIG
    /usr/local/bin/setup-telegram.sh
    log "Proton Pass login OK ✓"
fi

# ─── 3. Pull existing state from Proton Drive ───────────────────────────────

log "Pulling state from Proton Drive (proton:${SYNC_REMOTE_PATH}/)..."
if rclone_2fa copy "proton:${SYNC_REMOTE_PATH}/" "$OPENCLAW_HOME/" \
    --exclude-from "$EXCLUDE_FILE" \
    --create-empty-src-dirs \
    --log-level NOTICE 2>&1; then
    log "State pull complete ✓"
else
    warn "No existing state on Drive (first run?). Starting fresh."
fi

# ─── 4. Apply config template if no config exists ───────────────────────────

TEMPLATE="/opt/openclaw-proton/openclaw.json.template"
TEMPLATE_HASH_FILE="$OPENCLAW_HOME/.template-hash"

if [ ! -f "$OPENCLAW_HOME/openclaw.json" ]; then
    log "No config found — applying template..."
    cp "$TEMPLATE" "$OPENCLAW_HOME/openclaw.json"
    md5sum "$TEMPLATE" > "$TEMPLATE_HASH_FILE" 2>/dev/null || true
    log "Config template applied."
elif [ -f "$TEMPLATE_HASH_FILE" ] && ! md5sum --check "$TEMPLATE_HASH_FILE" --status 2>/dev/null; then
    warn "openclaw.json.template has changed since config was created."
    warn "Review the new template and update ~/.openclaw/openclaw.json if needed."
fi

# ─── 5. Generate IDENTITY.md from BOT_NAME ────────────────────────────────

IDENTITY_FILE="$OPENCLAW_HOME/workspace/IDENTITY.md"
if [ ! -f "$IDENTITY_FILE" ] || grep -q "^- \*\*Name:\*\*$" "$IDENTITY_FILE" 2>/dev/null; then
    BOT="${BOT_NAME:-OpenClaw}"
    log "Writing IDENTITY.md for $BOT..."
    mkdir -p "$OPENCLAW_HOME/workspace"
    cat > "$IDENTITY_FILE" <<EOF
# IDENTITY.md - Who Am I?

- **Name:** $BOT
- **Creature:** AI assistant
- **Vibe:** helpful, sharp, friendly
- **Emoji:** 🦞
EOF
fi

# ─── 5b. Write ENVIRONMENT.md (our setup docs — separate from OpenClaw's AGENTS.md) ─

ENV_FILE="$OPENCLAW_HOME/workspace/ENVIRONMENT.md"
log "Writing ENVIRONMENT.md..."
cat > "$ENV_FILE" <<'ENVEOF'
# Environment

You are running inside a Docker container with Proton Pass for secrets
and Proton Drive for state sync.

## Secrets (Proton Pass)

All secrets (API keys, tokens, passwords) are stored in **Proton Pass**,
accessible via `pass-cli`. The vault is called **"OpenClaw"**.

```bash
# List vaults
pass-cli vault list

# List items in the vault
pass-cli item list "OpenClaw"

# Get a password
pass-cli item view "pass://OpenClaw/ITEM_NAME/password"

# Get a username
pass-cli item view "pass://OpenClaw/ITEM_NAME/username"

# Generate a TOTP code (if 2FA is configured on the item)
pass-cli item totp "pass://OpenClaw/ITEM_NAME"
```

**NEVER send secrets through Telegram or any chat channel.**
Secrets are injected into the environment automatically via `pass-cli run`.

## Proton Drive sync

State syncs to Proton Drive every 60 seconds.
`~/.openclaw/local/` is excluded from sync — use it for local-only data.

## Interactive commands

For commands that need a terminal (e.g. `claude setup-token`), use `pty: true`
in the exec tool. This allocates a pseudo-TTY.

If a command produces a browser auth URL, forward it to the user via Telegram.

## Persistence

**Only data in `~/.openclaw/` persists across container restarts.**
System packages installed with `apt-get` are lost when the container restarts.
Prefer npm/npx packages or install tools to `~/.openclaw/local/` when possible.

## Browser

OpenClaw has a built-in browser tool powered by Playwright.
Do **NOT** use `apt-get install chromium` — it won't work in this container.

Install the browser engine with:

```bash
npx playwright install chromium
```

This installs to `~/.openclaw/.browsers/` and persists across restarts.

## Installing tools

You have passwordless sudo. Install whatever you need:

```bash
sudo apt-get update && sudo apt-get install -y <package>
npm install <package>
npx <package>
```

## Restarting the gateway

If you need to restart the gateway (e.g. after installing a browser):

```bash
restart-gateway
```

This gracefully stops the gateway and Docker automatically restarts the container.

## Tools

- `restart-gateway` — restart the OpenClaw gateway
- `pass-cli` — Proton Pass CLI (secrets)
- `rclone` — Proton Drive sync
- `node`, `npm`, `npx`, `curl`, `bash`, `grep`, `find` — standard tools
ENVEOF

# ─── 6. Load secret references ──────────────────────────────────────────────

log "Loading secret references..."
set -a
source /opt/openclaw-proton/secrets.env
set +a

# ─── 7. Start background Drive sync ─────────────────────────────────────────

log "Starting background sync (every ${SYNC_INTERVAL}s)..."
(
    while true; do
        sleep "$SYNC_INTERVAL"
        rclone_2fa copy "$OPENCLAW_HOME/" "proton:${SYNC_REMOTE_PATH}/" \
            --exclude-from "$EXCLUDE_FILE" \
            --log-level ERROR 2>&1 || true
    done
) &
SYNC_PID=$!

# Cleanup on exit
cleanup() {
    log "Shutting down..."
    kill "$APP_PID" 2>/dev/null || true
    kill "$SYNC_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    log "Final state push to Drive..."
    rclone_2fa copy "$OPENCLAW_HOME/" "proton:${SYNC_REMOTE_PATH}/" \
        --exclude-from "$EXCLUDE_FILE" \
        --log-level ERROR 2>&1 || true
    log "Goodbye 🦞"
}
trap cleanup SIGTERM SIGINT

# ─── 8. Start OpenClaw ──────────────────────────────────────────────────────
# pass-cli run resolves pass:// URIs in env vars, then starts the process.
# TELEGRAM_BOT_TOKEN passes through as-is (not a pass:// URI).

log "Starting OpenClaw gateway..."
log "Dashboard: http://127.0.0.1:18789/"
echo ""

pass-cli run -- node dist/index.js gateway run --allow-unconfigured &
APP_PID=$!
wait "$APP_PID"
