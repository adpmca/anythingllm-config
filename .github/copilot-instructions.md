# Copilot Instructions for anythingllm-config

## Repository purpose
- This repo is a **runtime configuration wrapper** for AnythingLLM, not the application source code.
- Primary artifacts are `docker-compose.yml`, `.env.dev`, and `.env.prod`; most work here is config, deployment, and environment tuning.

## Big picture architecture
- Two independent containerized AnythingLLM services are defined in `docker-compose.yml`:
  - `anythingllm-dev` uses image `mintplexlabs/anythingllm:master` and exposes `3005 -> 3001`.
  - `anythingllm-prod` uses image `mintplexlabs/anythingllm:latest` and exposes `3007 -> 3001`.
- Both containers mount host storage and a per-environment `.env` file into `/app/server/*` inside the container:
  - `anythingllm-dev` mounts `./.env.dev` → `/app/server/.env`
  - `anythingllm-prod` mounts `./.env.prod` → `/app/server/.env`
- Data flow for model calls: AnythingLLM → `GENERIC_OPEN_AI_BASE_PATH` (`http://host.docker.internal:4141/`) → **copilot-api** (running as a WSL2 systemd service) → GitHub Copilot.
- **WSL2 networking caveat (Windows 10):** `host.docker.internal` resolves to `192.168.65.254` (Docker's Windows bridge), but copilot-api binds to the WSL2 VM IP (e.g. `172.21.x.x`). A `netsh portproxy` rule bridges these. It is set up by `scripts/setup-port-proxy.ps1` and re-applied on every Windows logon via a scheduled task (because the WSL2 IP changes on restart).

## Critical workflows
- Start stack: `docker compose up -d` (from repo root in WSL)
- Restart after config changes: `docker compose up -d --force-recreate`
- Inspect service status: `docker compose ps`
- Tail logs: `docker compose logs -f anythingllm-dev` (or `anythingllm-prod`)
- Stop stack: `docker compose down`
- Backup storage (both envs): `bash scripts/backup.sh` from WSL repo root
- Re-apply port proxy after WSL restart: run `scripts\setup-port-proxy.ps1` as Administrator

## Project-specific conventions
- Keep `STORAGE_DIR=/app/server/storage` aligned between compose `environment` and mounted volume targets.
- Keep `JWT_SECRET` consistent between compose `environment:` block and the corresponding `.env.dev` / `.env.prod` file.
- `JWT_SECRET`, `SIG_KEY`, and `SIG_SALT` **must differ** between `.env.dev` and `.env.prod` to prevent dev tokens authenticating against prod.
- `anythingllm-dev` is intended to track newer upstream (`master`), while `anythingllm-prod` tracks stable (`latest`). Preserve this split unless explicitly changing release strategy.
- Use host-specific volume paths intentionally; current compose uses Linux-style absolute paths under `/home/ajay/...`.
- `.env` values are mostly quoted strings; preserve existing quoting style when editing.

## Integration points and dependencies
- **copilot-api** (`npx copilot-api@latest start`) runs as a WSL2 systemd user service (`~/.config/systemd/user/copilot-api.service`). Set up via `scripts/setup-copilot-api.sh`. Requires a one-time GitHub device auth on first run.
- Docker containers reach copilot-api via `host.docker.internal:4141`, bridged by a `netsh portproxy` rule managed by `scripts/setup-port-proxy.ps1`.
- Model/runtime knobs currently configured in `.env` include:
  - `LLM_PROVIDER=generic-openai`
  - `GENERIC_OPEN_AI_MODEL_PREF=gpt-4.1-2025-04-14`
  - `GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT=8000`
  - `GENERIC_OPEN_AI_MAX_TOKENS=4000`
- Container capability requirement includes `SYS_ADMIN`; keep unless validated safe to remove.
- The container process runs as uid/gid **1000** (`anythingllm`). Host storage directories must be owned by 1000:1000 or the SQLite DB will fail to open. Fix with: `sudo chown -R 1000:1000 /home/ajay/apps/anythingllm /home/ajay/apps/anythingllm-prod`

## Secrets and credentials
- `secrets/recovery-dev.txt` and `secrets/recovery-prod.txt` hold admin recovery codes for each environment; fill these in after first login setup.
- The entire `secrets/` directory and all `.env.*` files are gitignored — never remove them from `.gitignore`.

## Editing guidance for AI agents
- Prefer minimal, surgical edits in `docker-compose.yml`, `.env.dev`, and `.env.prod`; avoid broad refactors.
- When changing ports, image tags, or mounted paths, update both dev/prod blocks unless divergence is intentional.
- Do not rotate secrets (`JWT_SECRET`, `SIG_KEY`, `SIG_SALT`) unless user explicitly requests it.
- If adding new provider settings, keep naming consistent with existing `GENERIC_OPEN_AI_*` style.
- Document any non-obvious operational change in `README.md` (currently minimal).