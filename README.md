# anythingllm-config

Runtime configuration wrapper for two AnythingLLM Docker services (dev + prod).

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Defines both services |
| `.env.dev` | Environment config for `anythingllm-dev` (port 3005) |
| `.env.prod` | Environment config for `anythingllm-prod` (port 3007) |
| `scripts/backup.sh` | DR backup script — archives storage for both environments |
| `scripts/setup-cron.sh` | Installs the daily backup cron job in WSL (idempotent, safe to re-run) |
| `scripts/migrate-workspaces.sh` | Migrate workspaces from a source DB into the dev DB (skips existing slugs) |
| `scripts/setup-copilot-api.sh` | One-time setup: installs Node.js + registers copilot-api as a WSL systemd service |
| `scripts/setup-port-proxy.ps1` | One-time setup (Admin): Windows port proxy so Docker containers can reach copilot-api in WSL2 |
| `scripts/copilot-api.service.template` | Systemd unit file reference for copilot-api |
| `secrets/recovery-dev.txt` | Admin recovery code for dev (gitignored) |
| `secrets/recovery-prod.txt` | Admin recovery code for prod (gitignored) |

## Usage

Run all commands from the root of this repo on the Linux/WSL host.

```bash
# Start both services
docker compose up -d

# Restart after editing .env.dev or .env.prod
docker compose up -d --force-recreate

# Tail logs
docker compose logs -f anythingllm-dev
docker compose logs -f anythingllm-prod

# Check status
docker compose ps

# Stop
docker compose down
```

## Environments

- **Dev** — tracks `mintplexlabs/anythingllm:master`, port `3005`, config in `.env.dev`
- **Prod** — tracks `mintplexlabs/anythingllm:latest`, port `3007`, config in `.env.prod`

Storage volumes (`/home/ajay/apps/...`) live outside the repo on the host and are not tracked in git.

## Copilot API (LLM proxy)

AnythingLLM routes model calls to `http://host.docker.internal:4141/` (set via `GENERIC_OPEN_AI_BASE_PATH`), which is served by [copilot-api](https://github.com/nicepkg/copilot-api).

### First-time setup (registers as WSL autostart service)

```bash
# Inside WSL
bash /mnt/c/Apps/dev/anythingllm-config/anythingllm-config/scripts/setup-copilot-api.sh
```

This will:
1. Install `nvm` and Node.js LTS (if not present)
2. Create `~/.config/systemd/user/copilot-api.service`
3. Enable + start the service (auto-starts on every WSL boot)

### Windows port proxy (required for Docker access)

Docker containers reach the Windows host via `host.docker.internal` (`192.168.65.254`). copilot-api runs inside WSL2, which has its own virtual IP (e.g. `172.21.16.64`) that Docker can't reach directly. A Windows port proxy bridges the gap.

Run **once as Administrator** from PowerShell:

```powershell
PowerShell -ExecutionPolicy Bypass -File scripts\setup-port-proxy.ps1
```

This adds a `netsh portproxy` rule (`0.0.0.0:4141 → WSL2_IP:4141`) and registers a Windows scheduled task that re-runs automatically on every logon — required because the WSL2 IP changes on restart.

### Manage the service

```bash
systemctl --user status copilot-api
systemctl --user restart copilot-api
systemctl --user stop copilot-api
journalctl --user -u copilot-api -f   # live logs
```

### Manual run (without systemd)

```bash
npx copilot-api@latest start
```

## Backup (Disaster Recovery)

Run from the repo root via WSL (the script requires `bash`, `docker`, `rsync`, and `tar`).

```bash
# Backup both environments
wsl bash -c "cd /mnt/c/Apps/dev/anythingllm-config/anythingllm-config && bash scripts/backup.sh"

# Or from inside WSL directly
./scripts/backup.sh           # both
./scripts/backup.sh dev       # dev only
./scripts/backup.sh prod      # prod only
```

Archives are written to `backups/dev/` and `backups/prod/` as timestamped `.tar.gz` files.
The script uses `sqlite3 .backup` for a consistent DB snapshot (safe while containers are running)
and retains the last **7** backups per environment by default.

Each archive contains: `anythingllm.db`, `comkey/`, `models/`, `lancedb/`, `vector-cache/`, `push-notifications/`.

Override defaults:
```bash
BACKUP_DIR=/mnt/nas/anythingllm-backups RETAIN_COUNT=14 ./scripts/backup.sh
```

### Schedule automatic backups (WSL cron)

```bash
# Inside WSL — installs the daily 2am cron job
bash scripts/setup-cron.sh
```

Or manually add to `crontab -e`:
```bash
0 2 * * * cd /mnt/c/Apps/dev/anythingllm-config/anythingllm-config && bash scripts/backup.sh >> /tmp/anythingllm-backup.log 2>&1
```

### Restore

```bash
# Stop the target service
docker compose stop anythingllm-prod

# Extract backup over the storage directory
tar -xzf backups/prod/anythingllm-prod-<timestamp>.tar.gz -C /home/ajay/apps/anythingllm-prod/storage/

# Fix ownership and restart
sudo chown -R 1000:1000 /home/ajay/apps/anythingllm-prod
docker compose start anythingllm-prod
```

## First-time host setup

The storage directories must be owned by uid/gid **1000** (the `anythingllm` user inside the container). Run once on the host before the first `docker compose up`:

```bash
mkdir -p /home/ajay/apps/anythingllm/storage /home/ajay/apps/anythingllm-prod/storage
sudo chown -R 1000:1000 /home/ajay/apps/anythingllm /home/ajay/apps/anythingllm-prod
```

If you recreate those directories later, repeat the `chown` — otherwise both containers will fail with `unable to open database file`.