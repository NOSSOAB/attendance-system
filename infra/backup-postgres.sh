#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$BACKUP_DIR"
set -a
# shellcheck disable=SC1091
. "$ROOT_DIR/infra/.env"
set +a

tmp="$BACKUP_DIR/.attendance-$STAMP.sql.gz.tmp"
final="$BACKUP_DIR/attendance-$STAMP.sql.gz"
trap 'rm -f "$tmp"' EXIT

docker compose --env-file "$ROOT_DIR/infra/.env" \
  -f "$ROOT_DIR/infra/compose.production.yaml" exec -T postgres \
  pg_dumpall -U "$POSTGRES_USER" | gzip -9 > "$tmp"
gzip -t "$tmp"
mv "$tmp" "$final"
find "$BACKUP_DIR" -type f -name 'attendance-*.sql.gz' -mtime "+$KEEP_DAYS" -delete
echo "$final"
