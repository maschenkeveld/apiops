#!/usr/bin/env bash
# Read the Dev Portal ID from OpenBao (written by the PlatformOps konnect-eu-apiops-portal stack).
# Prints the portal_id on stdout. OpenBao is Vault-API-compatible (KV v2).
#
# Env: VAULT_TOKEN (required), VAULT_ADDR (default OpenBao), VAULT_PORTAL_PATH (default portal path)
source "$(dirname "$0")/lib.sh"

require_env VAULT_TOKEN
VAULT_ADDR="${VAULT_ADDR:-https://openbao.shared.pve-home.schenkeveld.io}"
VAULT_PORTAL_PATH="${VAULT_PORTAL_PATH:-kv/data/konnect/konnect-eu-apiops-portal/portal-details}"

log "Reading portal ID from OpenBao: $VAULT_PORTAL_PATH"
resp="$(curl -sS -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/$VAULT_PORTAL_PATH")"
portal_id="$(echo "$resp" | jq -r '.data.data.portal_id // empty')"
[ -n "$portal_id" ] || die "could not read portal_id from $VAULT_PORTAL_PATH ($(echo "$resp" | jq -r '.errors // "no portal_id field"'))"

ok "Resolved portal ID"
echo "$portal_id"
