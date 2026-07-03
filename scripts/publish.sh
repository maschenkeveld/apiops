#!/usr/bin/env bash
# Publish one API to the Dev Portal (spec + md-files docs + portal publication + gateway
# implementation link) via the shared scripts/publish-api.sh.
source "$(dirname "$0")/lib.sh"

APP="${1:?usage: publish.sh <app> <control-plane>}"
CP="${2:?usage: publish.sh <app> <control-plane>}"
require_env KONNECT_TOKEN PORTAL_ID

log "Publish to portal: $APP"
redocly bundle "apis/$APP/openapi-spec/openapi-spec.yaml" \
  -o "apis/$APP/openapi-spec/openapi-spec-bundled.yaml"

KONNECT_TOKEN="$KONNECT_TOKEN" \
PORTAL_ID="$PORTAL_ID" \
API_NAME="$APP" \
API_VERSION="$(major_version "$APP")" \
CONTROL_PLANE_NAME="$CP" \
API_HOST="$KONNECT_ADDR" \
SPEC_FILE="apis/$APP/openapi-spec/openapi-spec-bundled.yaml" \
  bash scripts/publish-api.sh

ok "Published: $APP"
