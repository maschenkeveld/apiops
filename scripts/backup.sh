#!/usr/bin/env bash
# Dump a Konnect control plane's full state to backups/. Prints the backup file path on stdout
# (logs go to stderr) so callers can capture it, e.g. FILE=$(scripts/backup.sh apiops-development dev).
#
# Usage: backup.sh <control-plane> [label]
source "$(dirname "$0")/lib.sh"

CP="${1:?usage: backup.sh <control-plane> [label]}"
LABEL="${2:-$CP}"
require_env KONNECT_TOKEN

mkdir -p backups
file="backups/kong-backup-${LABEL}-$(date +%Y%m%d_%H%M%S).yaml"

log "deck gateway dump: $CP → $file"
deck gateway dump \
  --konnect-addr "$KONNECT_ADDR" \
  --konnect-control-plane-name "$CP" \
  --konnect-token "$KONNECT_TOKEN" \
  --yes \
  -o "$file"

log "Backup size: $(wc -c < "$file") bytes"
ok "Backed up $CP"
echo "$file"
