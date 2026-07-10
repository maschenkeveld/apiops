#!/usr/bin/env bash
# Diff and sync one API's built deck config to a Konnect control plane.
# Sources the env-var files so the patches' ${{ env "DECK_*" }} resolve, and scopes
# the write with --select-tag so only this API's entities are touched.
# Set DRY_RUN=1 to diff only (no write).
source "$(dirname "$0")/lib.sh"

APP="${1:?usage: deploy.sh <app> <control-plane>}"
CP="${2:?usage: deploy.sh <app> <control-plane>}"
require_env KONNECT_TOKEN

FILE="apis/$APP/deck-file/generated/kong-plugined-and-patched.yaml"
[ -f "$FILE" ] || die "built config missing — run generate.sh first: $FILE"

load_env "$CP" "$APP"
export DECK_API_NAME="$APP"
DECK_API_VERSION="$(major_version "$APP")"
export DECK_API_VERSION

OAS_FILE="apis/$APP/openapi-spec/openapi-spec-bundled.yaml"
if [ -f "$OAS_FILE" ]; then
  DECK_OAS_SPEC_JSON="$(python3 -c "import yaml,json,sys; print(json.dumps(yaml.safe_load(open('$OAS_FILE'))))")"
  export DECK_OAS_SPEC_JSON
fi

deck_args=(
  "$FILE" shared/plugin-templates/plugin-templates.yaml
  --konnect-addr "$KONNECT_ADDR"
  --konnect-control-plane-name "$CP"
  --konnect-token "$KONNECT_TOKEN"
  --select-tag "$DECK_API_NAME"
  --select-tag "$DECK_API_VERSION"
)

log "deck gateway diff: $APP → $CP"
deck gateway diff "${deck_args[@]}"

if [ "${DRY_RUN:-0}" = "1" ]; then
  ok "Dry run (diff only): $APP"
  exit 0
fi

log "deck gateway sync: $APP → $CP"
deck gateway sync "${deck_args[@]}"
ok "Synced: $APP → $CP"
