#!/usr/bin/env bash
# setup-copilot-api.sh — Install Node.js (via nvm) and register copilot-api as
# a systemd user service that starts automatically on WSL boot.
#
# Run once from the repo root inside WSL:
#   bash scripts/setup-copilot-api.sh
#
# After this, copilot-api will be available at http://localhost:4141 (and
# http://host.docker.internal:4141 for Docker containers) on every WSL startup.

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

LINUX_HOME="/home/ajay"
NVM_DIR="$LINUX_HOME/.nvm"
SERVICE_NAME="copilot-api"
SERVICE_DIR="$LINUX_HOME/.config/systemd/user"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── 1. Install nvm if missing ─────────────────────────────────────────────────
if [[ ! -d "$NVM_DIR" ]]; then
  log "Installing nvm..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
else
  log "nvm already installed at $NVM_DIR"
fi

# Load nvm in this script session
export NVM_DIR
set +u  # nvm uses unbound vars internally
# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

# ── 2. Install Node.js LTS if missing ────────────────────────────────────────
if ! command -v node &>/dev/null; then
  log "Installing Node.js LTS..."
  nvm install --lts
  nvm use --lts
  nvm alias default node
else
  log "Node.js already installed: $(node --version)"
fi
set -u

NODE_BIN="$(dirname "$(nvm which current)")"
NPX_PATH="$NODE_BIN/npx"
log "Using npx at: $NPX_PATH"

# ── 3. Create systemd user service ───────────────────────────────────────────
mkdir -p "$SERVICE_DIR"

log "Writing $SERVICE_DIR/$SERVICE_NAME.service..."
cat > "$SERVICE_DIR/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Copilot API - OpenAI-compatible LLM proxy
After=network.target

[Service]
ExecStart=$NPX_PATH copilot-api@latest start
Restart=on-failure
RestartSec=10
Environment=HOME=$LINUX_HOME
Environment=PATH=$NODE_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

# ── 4. Enable lingering so service starts without a login session ─────────────
log "Enabling linger for user ajay..."
sudo loginctl enable-linger ajay

# ── 5. Reload systemd and enable / start the service ─────────────────────────
log "Enabling and starting $SERVICE_NAME service..."
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"
systemctl --user restart "$SERVICE_NAME"

sleep 3
log "Service status:"
systemctl --user status "$SERVICE_NAME" --no-pager || true

log ""
log "Setup complete. copilot-api is listening on http://localhost:4141"
log "Logs: journalctl --user -u $SERVICE_NAME -f"
