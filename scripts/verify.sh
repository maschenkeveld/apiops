#!/usr/bin/env bash
# Verify connectivity to a Konnect control plane (deck gateway ping).
source "$(dirname "$0")/lib.sh"

CP="${1:?usage: verify.sh <control-plane>}"
require_env KONNECT_TOKEN

log "deck gateway ping: $CP"
deck gateway ping \
  --konnect-addr "$KONNECT_ADDR" \
  --konnect-control-plane-name "$CP" \
  --konnect-token "$KONNECT_TOKEN"
ok "Reachable: $CP"
