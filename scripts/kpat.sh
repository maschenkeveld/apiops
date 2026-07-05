#!/usr/bin/env bash
# Read the Konnect PAT from OpenBao. Used by trigger-release.yaml when
# READ_FROM_OPENBAO=true (otherwise the token comes from the KONNECT_TOKEN secret).
# Prints the token on stdout.
#
# Env: VAULT_TOKEN (required), VAULT_ADDR (default OpenBao),
#      VAULT_SECRET_PATH (default: kv/konnect/kpat)
source "$(dirname "$0")/lib.sh"

require_env VAULT_TOKEN
VAULT_ADDR="${VAULT_ADDR:-https://openbao.shared.pve-home.schenkeveld.io}"
VAULT_SECRET_PATH="${VAULT_SECRET_PATH:-kv/konnect/kpat}"

log "Reading Konnect PAT from OpenBao: $VAULT_SECRET_PATH"
resp="$(curl -sS -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/$VAULT_SECRET_PATH")"
token="$(echo "$resp" | jq -r '.data.token // empty')"
[ -n "$token" ] || die "could not read token from $VAULT_SECRET_PATH ($(echo "$resp" | jq -rc '.errors // "no token field"'))"

ok "Resolved Konnect PAT"
echo "$token"
