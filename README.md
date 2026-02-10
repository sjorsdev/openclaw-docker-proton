# 🦞 OpenClaw + Proton

Self-hosted OpenClaw with secrets in Proton Pass and state on Proton Drive. The only startup secret is a Telegram bot token — everything else is configured via chat.

## Architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│  Your Personal      │     │  Bot Account (free)  │
│  Proton Account     │     │  openclaw-bot@proton  │
│                     │     │                       │
│  Pass: "OpenClaw"   │────▶│  Pass: receives       │
│  vault (you manage) │share│  shared vault (read)  │
│                     │     │                       │
│                     │     │  Drive: OpenClaw/      │
│                     │     │  (state sync, 5 GB)   │
└─────────────────────┘     └───────────┬───────────┘
                                        │
                            ┌───────────▼───────────┐
                            │  Docker Container      │
                            │                        │
                            │  Telegram setup bot    │
                            │    ↓ /setup via chat   │
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
- A bot Proton account (free works fine)
- A Telegram bot token (from [@BotFather](https://t.me/BotFather))

## One-Time Setup

### 1. Create the bot's Proton account

Sign up at [proton.me](https://proton.me) — e.g. `openclaw-bot@proton.me`. Free plan gives 5 GB Drive storage, more than enough.

**Important:** Log into [drive.proton.me](https://drive.proton.me) at least once with the bot account to initialize Drive encryption keys (rclone needs this).

### 2. Create a shared vault in Proton Pass

In **your personal** Proton Pass app:

1. Create a vault called **`OpenClaw`**
2. Add login items with your API keys:

   | Item Name      | Password field         |
   |---------------|------------------------|
   | Anthropic     | `sk-ant-api03-...`     |
   | Gateway Token | `pick-a-strong-token`  |

3. Share the vault → invite `openclaw-bot@proton.me` → **Viewer** permissions

### 3. Create a Telegram bot

Message [@BotFather](https://t.me/BotFather) on Telegram → `/newbot` → copy the token.

### 4. Clone and start

```bash
git clone <this-repo> openclaw-proton
cd openclaw-proton
./start.sh          # creates .env on first run
# Paste your Telegram bot token into .env
./start.sh          # builds and starts
```

### 5. Configure via Telegram

Message your bot on Telegram:

```
/setup YOUR_PIN openclaw-bot@proton.me your-bot-password
```

The bot verifies the PIN (from your `.env`), logs into Proton Pass, pulls state from Drive, and starts the full OpenClaw gateway. Done.

## What Goes Where

| Thing | Where | Managed by |
|-------|-------|------------|
| API keys, tokens | Proton Pass → "OpenClaw" vault | You, from your phone |
| Telegram token + PIN | `.env` (local, gitignored) | You, once |
| Proton credentials | Sent via Telegram `/setup` | You, on first boot |
| OpenClaw state | Proton Drive → `OpenClaw/` | Container, auto-synced |
| Config | `openclaw.json.template` → container | You, edit template |
| SQLite indexes | Container volume (local only) | OpenClaw, rebuilt on boot |

## Files

| File | Purpose |
|------|---------|
| `start.sh` | Clone OpenClaw, build images, start container |
| `stop.sh` | Graceful stop with final Drive sync |
| `.env.example` | Template (just Telegram token + bot name) |
| `secrets.env` | Maps env vars → `pass://` URIs for pass-cli |
| `openclaw.json.template` | OpenClaw config with `${VAR}` refs |
| `setup-telegram.sh` | Minimal Telegram bot for Proton credential setup |
| `rclone-exclude.txt` | Shared exclude patterns for Drive sync |
| `Dockerfile` | Extends OpenClaw image with pass-cli + rclone |
| `docker-compose.yml` | Container orchestration |
| `entrypoint.sh` | Boot: setup (if needed) → pull → start → sync |

## Adding a New Secret

1. In Proton Pass, add an item to the "OpenClaw" vault
2. Add a `pass://` mapping in `secrets.env`
3. Reference `${VAR_NAME}` in `openclaw.json.template`
4. Rebuild: `docker compose build && docker compose up -d`

## Adding a Channel (e.g. Signal)

1. Add the bot token to your "OpenClaw" vault in Proton Pass
2. Add the `pass://` mapping in `secrets.env`
3. Uncomment the channel section in `openclaw.json.template`
4. Rebuild and restart

## Customization

- **Bot name:** Set `BOT_NAME` in `.env` (default: `OpenClaw`)
- **Sync interval:** Set `SYNC_INTERVAL` in `.env` (default: 60 seconds)
- **Drive folder:** Set `SYNC_REMOTE_PATH` in `.env` (default: `OpenClaw`)
- **AI model:** Edit `agents.defaults.model` in `openclaw.json.template`
- **Expose publicly:** Remove `127.0.0.1:` from the port mapping in `docker-compose.yml`

## Troubleshooting

```bash
# View logs
docker compose logs -f

# Shell into running container
docker compose exec openclaw bash

# Check pass-cli status
docker compose exec openclaw pass-cli vault list

# Check rclone connectivity
docker compose exec openclaw rclone ls proton:OpenClaw/

# Re-run Proton setup (if session expired)
docker compose restart
# Then send /setup again via Telegram

# Rebuild from scratch
docker compose down -v    # ⚠️ wipes local state volume + credentials
./start.sh
```

## Security Notes

- `.env` contains only the Telegram bot token — no Proton passwords
- Proton credentials are sent once via Telegram (TLS encrypted) and stored in the container volume
- The bot account has **Viewer** access to your vault — it can't modify your secrets
- Revoke access instantly by unsharing the vault in Proton Pass
- State on Proton Drive is end-to-end encrypted by Proton
- Gateway token controls who can connect to the dashboard — pick a strong one
- The pass-cli session and encryption key persist in the Docker volume
