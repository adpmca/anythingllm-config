#!/usr/bin/env bash
# setup-cron.sh — Install the AnythingLLM backup cron job for the current user.
#
# Run from inside WSL:
#   bash scripts/setup-cron.sh
#
# Idempotent: safe to re-run. If the job already exists it won't be duplicated.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/tmp/anythingllm-backup.log"
CRON_MARKER="anythingllm-backup"
CRON_JOB="0 2 * * * cd $REPO_DIR && bash scripts/backup.sh >> $LOG_FILE 2>&1 # $CRON_MARKER"

echo "[$(date +%H:%M:%S)] Checking existing crontab..."

# Remove any previous version of this job, then append the current one
( crontab -l 2>/dev/null | grep -v "$CRON_MARKER"; echo "$CRON_JOB" ) | crontab -

echo "[$(date +%H:%M:%S)] Cron job installed:"
crontab -l | grep "$CRON_MARKER"

# Ensure cron daemon is running
if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
  echo "[$(date +%H:%M:%S)] Cron daemon is already running."
else
  echo "[$(date +%H:%M:%S)] Starting cron daemon..."
  sudo systemctl enable --now cron 2>/dev/null || sudo systemctl enable --now crond 2>/dev/null
fi

echo ""
echo "Backups will run daily at 2am. Logs: $LOG_FILE"
echo "To verify: crontab -l"
