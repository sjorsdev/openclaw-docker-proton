# OpenClaw + Proton

Self-hosted OpenClaw with secrets in Proton Pass and state on Proton Drive. The only startup secret is a Telegram bot token — everything else is configured via chat.

## Architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│  Your Personal      │     │  Bot Account (paid)  │
│  Proton Account     │     │  openclaw-bot@proton  │
│                     │     │                       │
│  Pass: "OpenClaw"   │────▶│  Pass: receives       │
│  vault (you manage) │share│  shared vault (read)  │
│                     │     │                       │
│                     │     │  Drive: OpenClaw/      │
│                     │     │  (state sync)         │
└─────────────────────┘     └───────────┬───────────┘
                                        │
                            ┌───────────▼───────────┐
                            │  Docker Container      │
                            │                        │
                            │  Telegram setup bot    │
                            │    ↓ /setup PIN        │
                            │  Browser auth (link)   │
                            │  pass-cli login        │
                            │  rclone pull state     │
                            │    ↓                   │
                            │  OpenClaw gateway      │
                            │    ↓ background        │
                            │  rclone push state     │
                            └────────────────────────┘
```

## Prerequisites

- Docker + Docker Compose
- Git
- A personal Proton account (paid, for vault sharing)
- A bot Proton account (paid — pass-cli requires a Pass subscription)
- A Telegram bot token (from [@BotFather](https://t.me/BotFather))

## One-Time Setup

### 1. Create the bot's Proton account

Sign up at [proton.me](https://proton.me) — e.g. `openclaw-bot@proton.me`. Upgrade to a paid plan (pass-cli requires Pass Plus or higher).

**Important:** Log into [drive.proton.me](https://drive.proton.me) at least once with the bot account to initialize Drive encryption keys (rclone needs this).

### 2. Create a shared vault in Proton Pass

In **your personal** Proton Pass app:

1. Create a vault called **`OpenClaw`**
2. Add login items:

   | Item Name      | Username field          | Password field         |
   |---------------|-------------------------|------------------------|
   | Gemini        |                         | Your Google AI API key |
   | Gateway Token |                         | Pick a strong token    |
   | Proton Bot    | `openclaw-bot@proton.me`| Bot's Proton password  |

3. If the bot account has 2FA, add the TOTP URI to the "Proton Bot" item
4. Share the vault → invite the bot account → **Viewer** permissions

### 3. Create a Telegram bot

Message [@BotFather](https://t.me/BotFather) on Telegram → `/newbot` → copy the token.

### 4. Clone and start

```bash
git clone <this-repo> openclaw-proton
cd openclaw-proton
./start.sh          # creates .env on first run
# Fill in TELEGRAM_BOT_TOKEN and SETUP_PIN in .env
./start.sh          # builds and starts
```

### 5. Configure via Telegram

Message your bot on Telegram:

```
/setup YOUR_PIN
```

The bot sends you a browser login link. Open it, log in with the bot's Proton account. No credentials go through Telegram. After login, the bot configures Drive sync and starts the OpenClaw gateway.

## What Goes Where

| Thing | Where | Managed by |
|-------|-------|------------|
| API keys, tokens | Proton Pass → "OpenClaw" vault | You, from your phone |
| Telegram token + PIN | `.env` (local, gitignored) | You, once |
| Proton login | Browser auth via link in Telegram | You, on first boot |
| Bot identity | Generated from `BOT_NAME` env var | entrypoint.sh |
| OpenClaw state | Proton Drive → `OpenClaw/` | Container, auto-synced |
| Config | `openclaw.json.template` → container | You, edit template |
| Local-only data | `~/.openclaw/local/` (not synced) | Container |

## Files

| File | Purpose |
|------|---------|
| `start.sh` | Clone OpenClaw, build images, start container |
| `stop.sh` | Graceful stop with final Drive sync |
| `.env.example` | Template (Telegram token + PIN + bot name) |
| `secrets.env` | Maps env vars → `pass://` URIs for pass-cli |
| `openclaw.json.template` | OpenClaw config with `${VAR}` refs |
| `setup-telegram.sh` | Telegram bot for browser-based Proton setup |
| `rclone-exclude.txt` | Exclude patterns for Drive sync |
| `Dockerfile` | Extends OpenClaw image with pass-cli + rclone |
| `docker-compose.yml` | Container orchestration |
| `entrypoint.sh` | Boot: setup → pull → identity → start → sync |

## Adding a New Secret

1. In Proton Pass, add an item to the "OpenClaw" vault
2. Add a `pass://` mapping in `secrets.env`
3. Reference `${VAR_NAME}` in `openclaw.json.template`
4. Rebuild: `docker compose build && docker compose up -d`

## Customization

- **Bot name:** Set `BOT_NAME` in `.env` (default: `OpenClaw`)
- **Sync interval:** Set `SYNC_INTERVAL` in `.env` (default: 60 seconds)
- **Drive folder:** Set `SYNC_REMOTE_PATH` in `.env` (default: `OpenClaw`)
- **AI model:** Edit `agents.defaults.model.primary` in `openclaw.json.template`
- **Expose publicly:** Remove `127.0.0.1:` from the port mapping in `docker-compose.yml`

## Troubleshooting

```bash
# View logs
docker compose logs -f

# Shell into running container
docker compose exec openclaw bash

# Check pass-cli status
docker compose exec openclaw pass-cli vault list

# Re-run Proton setup (if session expired)
docker compose restart
# Then send /setup again via Telegram

# Rebuild from scratch
docker compose down -v    # wipes local state volume + credentials
./start.sh
```

## Security Notes

- `.env` contains only the Telegram bot token and setup PIN — no Proton passwords
- Proton login uses browser-based auth — no credentials go through Telegram
- The "Proton Bot" password in Pass is only used for Drive sync (rclone)
- The bot account has **Viewer** access to your vault — it can't modify your secrets
- Revoke access instantly by unsharing the vault in Proton Pass
- State on Proton Drive is end-to-end encrypted by Proton
- Gateway token controls who can connect to the dashboard — pick a strong one
- The pass-cli session and encryption key persist in the Docker volume
- 2FA is supported — TOTP codes are generated from the "Proton Bot" item in Pass
