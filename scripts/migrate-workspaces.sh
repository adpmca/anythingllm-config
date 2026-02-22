#!/usr/bin/env bash
# migrate-workspaces.sh — Copy workspaces from a source AnythingLLM SQLite DB
# into the current dev DB. Skips workspaces whose slug already exists (idempotent).
#
# Usage (from WSL, repo root):
#   bash scripts/migrate-workspaces.sh [source_db_path]
#
# Default source: /mnt/c/Apps/dev/anythingllm/storage/anythingllm.db
# Target:         /home/ajay/apps/anythingllm/storage/anythingllm.db (dev)

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

SOURCE_DB="${1:-/mnt/c/Apps/dev/anythingllm/storage/anythingllm.db}"
TARGET_DB="/home/ajay/apps/anythingllm/storage/anythingllm.db"
SQLITE_IMAGE="alpine/sqlite:latest"

[[ -f "$SOURCE_DB" ]] || { echo "ERROR: Source DB not found: $SOURCE_DB"; exit 1; }
[[ -f "$TARGET_DB" ]] || { echo "ERROR: Target DB not found: $TARGET_DB"; exit 1; }

SOURCE_DIR="$(dirname "$SOURCE_DB")"
TARGET_DIR="$(dirname "$TARGET_DB")"

log "Source: $SOURCE_DB"
log "Target: $TARGET_DB"
echo ""

log "Workspaces in source DB:"
docker run --rm -v "${SOURCE_DIR}:/src:ro" "$SQLITE_IMAGE" \
  /src/anythingllm.db "SELECT id, name, slug FROM workspaces ORDER BY id;"
echo ""

log "Workspaces currently in dev DB:"
docker run --rm -v "${TARGET_DIR}:/target:ro" "$SQLITE_IMAGE" \
  /target/anythingllm.db "SELECT id, name, slug FROM workspaces ORDER BY id;"
echo ""

log "Migrating workspaces (INSERT OR IGNORE — skips existing slugs)..."

# Dump INSERT statements from source, replay into target
docker run --rm -v "${SOURCE_DIR}:/src:ro" "$SQLITE_IMAGE" \
  /src/anythingllm.db \
  ".mode insert workspaces
   SELECT name, slug, vectorTag, createdAt, openAiTemp, openAiHistory, lastUpdatedAt,
          openAiPrompt, similarityThreshold, topN, chatMode, pfpFilename, chatProvider,
          agentModel, agentProvider, queryRefusalResponse, vectorSearchMode, chatModel
   FROM workspaces;" \
| sed 's/^INSERT INTO "workspaces"/INSERT OR IGNORE INTO workspaces/' \
| docker run --rm -i -v "${TARGET_DIR}:/target" "$SQLITE_IMAGE" /target/anythingllm.db

log "Migration complete."
echo ""

log "Workspaces in dev DB after migration:"
docker run --rm -v "${TARGET_DIR}:/target:ro" "$SQLITE_IMAGE" \
  /target/anythingllm.db "SELECT id, name, slug FROM workspaces ORDER BY id;"
