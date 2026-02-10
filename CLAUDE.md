# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Docker wrapper that runs [OpenClaw](https://github.com/nicepersonality/open-claw) with secrets from Proton Pass and state synced to Proton Drive. No application code lives here — only Docker infrastructure and shell scripts.

## Architecture

The only startup secret is a Telegram bot token in `.env`. On first boot, a minimal Telegram bot (`setup-telegram.sh`) waits for the user to send `/setup email password` via chat. This logs into Proton Pass and configures rclone for Drive sync. After that, OpenClaw starts with `pass-cli run` which resolves `pass://` URIs from `secrets.env` into real env var values for the `${VAR}` references in the config.

Two Proton accounts are involved: the user's personal account (owns a shared Pass vault with API keys) and a bot account (receives the shared vault, runs in the container).

Pass-cli session, rclone config, and the encryption key all persist in the Docker volume (`/home/node/.openclaw/`) via redirected XDG paths — they survive container restarts. If the session expires, the setup bot runs again on next boot.

## Commands

```bash
./start.sh              # Clone OpenClaw, build both images, start container
./stop.sh               # Graceful stop (waits for final Drive sync)
docker compose logs -f   # View logs
docker compose restart   # Restart without rebuild
docker compose build && docker compose up -d  # Rebuild and restart
docker compose down -v   # Full reset (wipes volume + credentials)
```

On first run, `start.sh` creates `.env` from `.env.example`. You only need to add `TELEGRAM_BOT_TOKEN`. Proton credentials come via Telegram `/setup` command.

## File Roles

- `start.sh` — Orchestrates first-time setup: clones OpenClaw repo into `./open-claw/`, builds the base `openclaw:local` image, then builds the Proton wrapper image and starts the container.
- `entrypoint.sh` — Container boot (7 steps): generate encryption key → check pass-cli login (run setup bot if needed) → pull state from Drive → apply config template → load secret references → start sync loop → start OpenClaw via `pass-cli run`.
- `setup-telegram.sh` — Minimal curl-based Telegram bot. Waits for `/setup email password`, logs into pass-cli, configures rclone, exits. Only runs when pass-cli has no active session.
- `secrets.env` — Maps env var names to `pass://` URIs. Sourced before `pass-cli run` which resolves them. Telegram token is NOT here (comes directly from `.env`).
- `openclaw.json.template` — OpenClaw config (JSON5) with `${VAR}` placeholders. Copied to `~/.openclaw/openclaw.json` on first boot only.
- `rclone-exclude.txt` — Shared exclude patterns for all rclone operations (pull, push, final sync).
- `docker-compose.yml` — Single service, named volume for state + credentials, port bound to `127.0.0.1:18789`.
- `.env` — Gitignored. Only holds `TELEGRAM_BOT_TOKEN` and `BOT_NAME`.

## Adding Secrets or Channels

1. Add the item in Proton Pass (in the "OpenClaw" vault)
2. Add the `pass://` mapping in `secrets.env`
3. Reference `${VAR_NAME}` in `openclaw.json.template`
4. Rebuild: `docker compose build && docker compose up -d`

## Important Notes

- OpenClaw does NOT support `pass://` URIs natively — it only supports `${VAR}` env substitution. The `pass-cli run` wrapper resolves `pass://` URIs from env vars before launching Node.
- The base OpenClaw image is built from `./open-claw/` (cloned by `start.sh`), then this project's `Dockerfile` layers on top.
- SQLite databases are excluded from Drive sync — rebuilt locally on boot.
- Sync interval configurable via `SYNC_INTERVAL` in `.env` (default: 60s).
- `stop.sh` uses a 30s grace period for the final sync.
- Bot name configurable via `BOT_NAME` in `.env` (default: `OpenClaw`).
- Credential persistence: XDG paths are redirected into the Docker volume so pass-cli session and rclone config survive restarts.
