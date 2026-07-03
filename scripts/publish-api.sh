#!/usr/bin/env bash
#
# publish-api.sh — publish a single API to the Konnect Dev Portal.
#
# This is the parameterized, CI-friendly refactor of the legacy scripts now in scripts/old/
# (full.sh / deploy-api-to-portal.sh / apispec.sh / apidocs.sh / apipublish.sh).
# All configuration comes from environment variables (nothing hardcoded), so it can be
# called from a GitHub Actions matrix or run locally.
#
# It performs the full publish flow for one API:
#   1. Upsert the API in the Konnect API registry and upload its OpenAPI spec
#   2. Upload every markdown file under apis/<name>/md-files/ as an API document
#   3. Publish the API to the Dev Portal (PORTAL_ID)
#   4. Resolve the API's running gateway service (by tags) and link it as an
#      API implementation
#
# Required environment variables:
#   KONNECT_TOKEN        Konnect PAT (kpat_...)
#   PORTAL_ID            Target Dev Portal ID (read from Vault in CI)
#   API_NAME             API name; must match the apis/<API_NAME> folder
#   CONTROL_PLANE_NAME   Konnect control plane the gateway service lives in
#
# Optional environment variables:
#   API_VERSION          Defaults to "v1"
#   API_HOST             Konnect region host; defaults to https://eu.api.konghq.com
#   SPEC_FILE            Defaults to apis/<API_NAME>/openapi-spec/openapi-spec.yaml
#                        (CI passes the bundled spec here)
#   PORTAL_VISIBILITY    "public" (default) or "private"
#
# Run from the repository root. Requires curl, jq and yq on PATH.

set -euo pipefail

# --- Config / validation ----------------------------------------------------
API_HOST="${API_HOST:-https://eu.api.konghq.com}"
API_VERSION="${API_VERSION:-v1}"
PORTAL_VISIBILITY="${PORTAL_VISIBILITY:-public}"
SPEC_FILE="${SPEC_FILE:-apis/${API_NAME:-}/openapi-spec/openapi-spec.yaml}"

require() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "❌ Required environment variable '$name' is not set" >&2
    exit 1
  fi
}

require KONNECT_TOKEN
require PORTAL_ID
require API_NAME
require CONTROL_PLANE_NAME

if [ ! -f "$SPEC_FILE" ]; then
  echo "❌ Spec file not found: $SPEC_FILE" >&2
  exit 1
fi

API_SLUG=$(echo "${API_NAME}-${API_VERSION}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
OAS_SPEC_CONTENT=$(yq -o=json "$SPEC_FILE" | jq -Rs .)

auth=(-H "Authorization: Bearer $KONNECT_TOKEN")
json=(-H "Content-Type: application/json")

echo "▶ Publishing API '$API_NAME' ($API_VERSION) to portal $PORTAL_ID via $API_HOST"

# --- 1. Upsert API + spec ---------------------------------------------------
APIS_RESPONSE=$(curl -s -G "$API_HOST/v3/apis" "${auth[@]}" \
  --data-urlencode "filter[name]=$API_NAME" \
  --data-urlencode "filter[version]=$API_VERSION")

API_EXISTS=$(echo "$APIS_RESPONSE" | jq -r '.data | length')

if [ "$API_EXISTS" -gt 0 ]; then
  API_ID=$(echo "$APIS_RESPONSE" | jq -r '.data[0].id')
  SPEC_ID=$(echo "$APIS_RESPONSE" | jq -r '.data[0].api_spec_ids[0]')
  echo "  ✅ Found existing API $API_ID (spec $SPEC_ID); updating spec"
  curl -s --request PATCH \
    --url "$API_HOST/v3/apis/$API_ID/versions/$SPEC_ID" \
    -H "Accept: application/json, application/problem+json" \
    "${auth[@]}" "${json[@]}" \
    --data "{\"spec\": {\"content\": $OAS_SPEC_CONTENT}}" >/dev/null
else
  echo "  ➕ Creating new API"
  CREATE_RESPONSE=$(curl -s -X POST "$API_HOST/v3/apis" "${auth[@]}" "${json[@]}" \
    --data "{
      \"name\": \"$API_NAME\",
      \"version\": \"$API_VERSION\",
      \"slug\": \"$API_SLUG\",
      \"labels\": {\"env\": \"$CONTROL_PLANE_NAME\"},
      \"spec_content\": $OAS_SPEC_CONTENT
    }")
  API_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id')
fi

if [ -z "${API_ID:-}" ] || [ "$API_ID" = "null" ]; then
  echo "❌ Could not determine API ID after upsert" >&2
  exit 1
fi

# --- 2. Upload markdown docs ------------------------------------------------
MD_DIR="apis/$API_NAME/md-files"
if [ -d "$MD_DIR" ]; then
  shopt -s nullglob
  for MD_FILE in "$MD_DIR"/*.md; do
    BASE_NAME="$(basename "${MD_FILE%.*}")"
    DOC_TITLE=$(echo "$BASE_NAME" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
    DOC_SLUG=$(echo "$BASE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    MD_CONTENT=$(jq -Rs . < "$MD_FILE")

    DOCS_RESPONSE=$(curl -s -X GET "$API_HOST/v3/apis/$API_ID/documents" "${auth[@]}")
    EXISTING_DOC_ID=$(echo "$DOCS_RESPONSE" | jq -r --arg SLUG "$DOC_SLUG" '.data[] | select(.slug == $SLUG) | .id')

    if [ -n "$EXISTING_DOC_ID" ]; then
      echo "  📝 Updating document '$DOC_SLUG'"
      curl -s -X PATCH "$API_HOST/v3/apis/$API_ID/documents/$EXISTING_DOC_ID" "${auth[@]}" "${json[@]}" \
        --data "{\"title\": \"$DOC_TITLE\", \"slug\": \"$DOC_SLUG\", \"content\": $MD_CONTENT, \"status\": \"published\"}" >/dev/null
    else
      echo "  📝 Creating document '$DOC_SLUG'"
      curl -s -X POST "$API_HOST/v3/apis/$API_ID/documents" "${auth[@]}" "${json[@]}" \
        --data "{\"title\": \"$DOC_TITLE\", \"slug\": \"$DOC_SLUG\", \"content\": $MD_CONTENT, \"status\": \"published\"}" >/dev/null
    fi
  done
  shopt -u nullglob
else
  echo "  (no md-files/ directory; skipping docs)"
fi

# --- 3. Publish to portal ---------------------------------------------------
echo "  🚀 Publishing to portal $PORTAL_ID (visibility: $PORTAL_VISIBILITY)"
curl -s -X PUT "$API_HOST/v3/apis/$API_ID/publications/$PORTAL_ID" "${auth[@]}" "${json[@]}" \
  -d "{
    \"visibility\": \"$PORTAL_VISIBILITY\",
    \"auto_approve_registrations\": true,
    \"auth_strategy_ids\": null
  }" >/dev/null

# --- 4. Link API to its running gateway service (implementation) ------------
echo "  🔗 Linking API to gateway service in control plane '$CONTROL_PLANE_NAME'"
CP_RESPONSE=$(curl -s -X GET "$API_HOST/v2/control-planes" "${auth[@]}")
CP_ID=$(echo "$CP_RESPONSE" | jq -r ".data[] | select(.name == \"$CONTROL_PLANE_NAME\") | .id")
if [ -z "$CP_ID" ] || [ "$CP_ID" = "null" ]; then
  echo "❌ No control plane found named: $CONTROL_PLANE_NAME" >&2
  exit 1
fi

SERVICES_RESPONSE=$(curl -s -X GET \
  "$API_HOST/v2/control-planes/$CP_ID/core-entities/services?tags=$API_NAME,$API_VERSION" "${auth[@]}")
SERVICE_ID=$(echo "$SERVICES_RESPONSE" | jq -r '.data[0].id // empty')
if [ -z "$SERVICE_ID" ]; then
  echo "❌ No gateway service found tagged: $API_NAME, $API_VERSION" >&2
  exit 1
fi

IMPLS=$(curl -s --request GET "$API_HOST/v3/api-implementations" \
  -H "Accept: application/json, application/problem+json" "${auth[@]}" "${json[@]}")
IMPL_EXISTS=$(echo "$IMPLS" | jq --arg sid "$SERVICE_ID" '[.data[] | select(.service.id == $sid)] | length')

if [ "$IMPL_EXISTS" -gt 0 ]; then
  echo "  ✅ Implementation already exists for service $SERVICE_ID"
else
  echo "  ➕ Creating implementation for service $SERVICE_ID"
  curl -s -X POST "$API_HOST/v3/apis/$API_ID/implementations" \
    -H "Accept: application/json, application/problem+json" "${auth[@]}" "${json[@]}" \
    -d "{\"service\": {\"control_plane_id\": \"$CP_ID\", \"id\": \"$SERVICE_ID\"}}" >/dev/null
fi

echo "✅ Done: $API_NAME ($API_VERSION) published to portal $PORTAL_ID"
