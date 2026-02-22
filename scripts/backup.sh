#!/usr/bin/env bash
# backup.sh — AnythingLLM storage backup for disaster recovery
#
# Usage:
#   ./scripts/backup.sh              # backup both dev and prod
#   ./scripts/backup.sh dev          # backup dev only
#   ./scripts/backup.sh prod         # backup prod only
#
# Backups are written to BACKUP_DIR (default: ./backups) as timestamped .tar.gz archives.
# The SQLite DB is safely snapshotted using `sqlite3 .backup` before the tar is created.
# Keeps the last RETAIN_COUNT backups per environment (older ones are pruned).
#
# Run from the root of this repo on the Linux/WSL host.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BACKUP_DIR="${BACKUP_DIR:-$REPO_ROOT/backups}"
RETAIN_COUNT="${RETAIN_COUNT:-7}"  # keep last N backups per environment

DEV_STORAGE="/home/ajay/apps/anythingllm/storage"
PROD_STORAGE="/home/ajay/apps/anythingllm-prod/storage"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SQLITE_IMAGE="alpine/sqlite:latest"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

require_cmd() { command -v "$1" &>/dev/null || die "'$1' not found in PATH"; }

# Safe SQLite snapshot using .backup command (works while container is running)
sqlite_backup() {
  local src_dir="$1"
  local dest_file="$2"
  docker run --rm \
    -v "${src_dir}:/src:ro" \
    -v "$(dirname "$dest_file"):/dest" \
    "$SQLITE_IMAGE" \
    /src/anythingllm.db ".backup /dest/$(basename "$dest_file")"
}

backup_env() {
  local env="$1"          # dev | prod
  local storage="$2"      # host path to storage dir

  log "Starting $env backup..."

  [[ -d "$storage" ]] || die "Storage directory not found: $storage"

  local out_dir="$BACKUP_DIR/$env"
  mkdir -p "$out_dir"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  # 1. Safe DB snapshot (consistent read, no corruption risk)
  log "  Snapshotting SQLite DB..."
  if [[ -f "$storage/anythingllm.db" ]]; then
    sqlite_backup "$storage" "$tmp_dir/anythingllm.db"
  else
    log "  WARNING: anythingllm.db not found, skipping DB snapshot"
  fi

  # 2. Copy rest of storage (vectors, documents, models, etc.) excluding the live DB
  log "  Copying storage files..."
  rsync -a --exclude="anythingllm.db" --exclude="*.db-wal" --exclude="*.db-shm" \
    "$storage/" "$tmp_dir/storage/"

  # Include the safe snapshot in the storage copy
  [[ -f "$tmp_dir/anythingllm.db" ]] && cp "$tmp_dir/anythingllm.db" "$tmp_dir/storage/anythingllm.db"

  # 3. Create timestamped archive
  local archive="$out_dir/anythingllm-${env}-${TIMESTAMP}.tar.gz"
  log "  Creating archive: $archive"
  tar -czf "$archive" -C "$tmp_dir/storage" .

  log "  Backup size: $(du -sh "$archive" | cut -f1)"

  # 4. Prune old backups, keep last RETAIN_COUNT
  local count
  count=$(ls -1t "$out_dir"/anythingllm-${env}-*.tar.gz 2>/dev/null | wc -l)
  if (( count > RETAIN_COUNT )); then
    log "  Pruning old backups (keeping $RETAIN_COUNT)..."
    ls -1t "$out_dir"/anythingllm-${env}-*.tar.gz | tail -n "+$((RETAIN_COUNT + 1))" | xargs rm -f
  fi

  log "$env backup complete → $archive"
}

# ── Main ──────────────────────────────────────────────────────────────────────
require_cmd docker
require_cmd rsync
require_cmd tar

mkdir -p "$BACKUP_DIR"

TARGET="${1:-all}"

case "$TARGET" in
  dev)  backup_env dev  "$DEV_STORAGE" ;;
  prod) backup_env prod "$PROD_STORAGE" ;;
  all)
    backup_env dev  "$DEV_STORAGE"
    backup_env prod "$PROD_STORAGE"
    ;;
  *)    die "Unknown target '$TARGET'. Use: dev | prod | all" ;;
esac

log "All done. Backups stored in: $BACKUP_DIR"
