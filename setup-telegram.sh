#!/bin/bash
# Minimal Telegram bot for initial Proton Pass setup.
# No credentials go through Telegram — uses browser-based auth.
# Runs only when pass-cli is not yet configured. Exits after successful login.
set -euo pipefail

log() { echo "🦞 [setup] $1"; }
warn() { echo "⚠️  [setup] $1"; }

API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
OFFSET=0
SETUP_CODE="${SETUP_PIN:?SETUP_PIN not set in .env}"

send_msg() {
    local chat_id="$1" text="$2"
    node -e "
        const https = require('https');
        const data = JSON.stringify({
            chat_id: process.argv[1],
            text: process.argv[2]
        });
        const req = https.request('${API}/sendMessage', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Content-Length': data.length }
        });
        req.end(data);
    " "$chat_id" "$text" 2>/dev/null || true
}

# Extract updates from Telegram API response via stdin
json_field() {
    node -e "
        const data = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
        for (const u of data.result || []) {
            const m = u.message || {};
            const fields = {
                id: u.update_id,
                chat: (m.chat || {}).id || '',
                text: m.text || ''
            };
            // Tab-separated for safe shell parsing
            console.log([fields.id, fields.chat, fields.text].join('\t'));
        }
    " 2>/dev/null
}

log "Waiting for setup via Telegram..."
log "Send: /setup PIN"

while true; do
    RESPONSE=$(curl -s --max-time 35 \
        "$API/getUpdates?offset=$OFFSET&timeout=30" 2>/dev/null \
        || echo '{"result":[]}')

    while IFS=$'\t' read -r UPDATE_ID CHAT_ID TEXT; do
        [ -z "$UPDATE_ID" ] && continue
        OFFSET=$((UPDATE_ID + 1))

        case "$TEXT" in
            /setup\ *)
                # Format: /setup PIN
                CODE=$(echo "$TEXT" | awk '{print $2}')

                if [ "$CODE" != "$SETUP_CODE" ]; then
                    send_msg "$CHAT_ID" "Invalid PIN."
                    log "Rejected: wrong PIN from chat $CHAT_ID"
                    continue
                fi

                send_msg "$CHAT_ID" "Starting Proton Pass login..."

                # Run pass-cli in background, capture output to temp file
                LOGIN_LOG=$(mktemp)
                pass-cli login > "$LOGIN_LOG" 2>&1 &
                LOGIN_PID=$!

                # Watch for browser auth URL and forward to Telegram
                URL_SENT=false
                while kill -0 "$LOGIN_PID" 2>/dev/null; do
                    if [ "$URL_SENT" = false ] && grep -q 'https://account.proton.me' "$LOGIN_LOG" 2>/dev/null; then
                        AUTH_URL=$(grep -o 'https://account.proton.me[^ ]*' "$LOGIN_LOG")
                        send_msg "$CHAT_ID" "Open this link to log in:

$AUTH_URL"
                        URL_SENT=true
                        log "Auth URL sent to Telegram"
                    fi
                    sleep 1
                done

                wait "$LOGIN_PID"
                LOGIN_EXIT=$?
                cat "$LOGIN_LOG"

                # Parse email from pass-cli output
                EMAIL=$(grep -oP 'Login performed by \K\S+' "$LOGIN_LOG" || true)
                rm -f "$LOGIN_LOG"

                if [ "$LOGIN_EXIT" -eq 0 ] && [ -n "$EMAIL" ]; then
                    log "Login successful for $EMAIL"

                    # Retrieve bot password from Proton Pass for rclone
                    log "Configuring Proton Drive sync..."
                    PROTON_PASS=$(pass-cli item view "pass://OpenClaw/Proton Bot/password" 2>/dev/null | tr -d '\n' || true)

                    if [ -n "$PROTON_PASS" ]; then
                        RCLONE_PASS=$(rclone obscure "$PROTON_PASS")
                        cat > "$RCLONE_CONFIG" <<REOF
[proton]
type = protondrive
username = $EMAIL
password = $RCLONE_PASS
REOF
                        unset RCLONE_PASS PROTON_PASS
                        log "Proton Drive configured ✓"
                    else
                        warn "No 'Proton Bot' item found in OpenClaw vault."
                        warn "Drive sync disabled. Add item to vault and restart to enable."
                    fi

                    # Store chat ID for potential allowlist seeding
                    echo "$CHAT_ID" > "$OPENCLAW_HOME/.setup-chat-id"

                    send_msg "$CHAT_ID" "Logged in as $EMAIL! Starting OpenClaw..."
                    exit 0
                else
                    send_msg "$CHAT_ID" "Login failed. Try again."
                    log "Login failed"
                fi
                ;;
            *)
                [ -n "$TEXT" ] && send_msg "$CHAT_ID" \
                    "OpenClaw Setup — send /setup PIN to begin."
                ;;
        esac
    done < <(echo "$RESPONSE" | json_field)
done
