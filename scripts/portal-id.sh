#!/usr/bin/env bash
# Read the Dev Portal ID from OpenBao. Optional path — used by publish-to-portal.yaml only when
# read_from_openbao=true (otherwise the portal ID comes from an env var / GitHub variable).
# Prints portal_id on stdout.
#
# The PlatformOps stacks write portal_id into their connection-details secret. The OpenBao
# ClusterSecretStore is KV v1 (mount kv), so the value is at `.data.portal_id` (no nested data).
#
# Env: VAULT_TOKEN (required), VAULT_ADDR (default OpenBao),
#      VAULT_SECRET_PATH (default: production connection-details)
source "$(dirname "$0")/lib.sh"

require_env VAULT_TOKEN
VAULT_ADDR="${VAULT_ADDR:-https://openbao.shared.pve-home.schenkeveld.io}"
VAULT_SECRET_PATH="${VAULT_SECRET_PATH:-kv/konnect/konnect-eu-apiops-production/connection-details}"

log "Reading portal ID from OpenBao: $VAULT_SECRET_PATH"
resp="$(curl -sS -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/$VAULT_SECRET_PATH")"
portal_id="$(echo "$resp" | jq -r '.data.portal_id // empty')"
[ -n "$portal_id" ] || die "could not read portal_id from $VAULT_SECRET_PATH ($(echo "$resp" | jq -rc '.errors // "no portal_id field"'))"

ok "Resolved portal ID"
echo "$portal_id"
