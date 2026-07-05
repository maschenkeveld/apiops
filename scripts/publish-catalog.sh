#!/usr/bin/env bash
# Publishes APIs to the Konnect API Catalog and developer portals.
# Driven by apis/$APP/konnect.yaml:
#
#   catalog: true
#   portals:
#     - apiops-developer-portal
#     - apiops-production-portal
#   gateways:
#     - control_plane: apiops-development
#       service: alice
#     - control_plane: apiops-production
#       service: alice
#
# One catalog entry is created per gateway using a naming convention:
#   control plane containing "dev"  → {app}-dev entry, matched to portals containing "dev"
#   control plane containing "prod" → {app}    entry, matched to portals containing "prod"
# All IDs are resolved by name at runtime — nothing hardcoded.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

: "${KONNECT_TOKEN:?KONNECT_TOKEN must be set}"
: "${APPS_LIST:?APPS_LIST must be set}"
: "${KONNECT_REGION:=eu}"

BASE_URL="https://${KONNECT_REGION}.api.konghq.com"
AUTH=(-H "Authorization: Bearer $KONNECT_TOKEN" -H "Content-Type: application/json")

# ---------- helpers --------------------------------------------------------

konnect_get()   { curl -sf "$BASE_URL$1" "${AUTH[@]}"; }
konnect_post()  { curl -sf -X POST  "$BASE_URL$1" "${AUTH[@]}" -d "$2"; }
konnect_put()   { curl -sf -X PUT   "$BASE_URL$1" "${AUTH[@]}" -d "$2"; }
konnect_patch() { curl -sf -X PATCH "$BASE_URL$1" "${AUTH[@]}" -d "$2"; }
konnect_delete(){ curl -sf -X DELETE "$BASE_URL$1" "${AUTH[@]}"; }

portal_id_for() {
  local name="$1"
  local encoded; encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))")
  local id; id=$(konnect_get "/v3/portals?filter%5Bname%5D=${encoded}" \
    | jq -r '.data[0].id // empty')
  [ -n "$id" ] || die "portal not found: $name"
  echo "$id"
}

cp_id_for() {
  local name="$1"
  local encoded; encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))")
  konnect_get "/v2/control-planes?filter%5Bname%5D=${encoded}" | jq -r '.data[0].id // empty'
}

service_id_for() {
  local cp_id="$1" name="$2"
  konnect_get "/v2/control-planes/$cp_id/core-entities/services" | \
    jq -r ".data[] | select(.name==\"$name\") | .id" | head -1
}

upsert_api() {
  local name="$1" desc="$2"
  local id; id=$(konnect_get "/v3/apis?filter%5Bname%5D=${name}" | jq -r '.data[0].id // empty')
  if [ -z "$id" ]; then
    id=$(konnect_post "/v3/apis" "{\"name\":\"$name\",\"description\":\"$desc\"}" | jq -r '.id')
    log "  created API: $name"
  fi
  echo "$id"
}

upsert_version() {
  local api_id="$1" spec_file="$2"
  local spec_json; spec_json=$(python3 -c \
    "import yaml,json,sys; print(json.dumps(yaml.safe_load(open('$spec_file'))))" 2>/dev/null \
    || yq -o=json . "$spec_file")
  local spec_json_escaped; spec_json_escaped=$(echo "$spec_json" | jq -Rs .)

  local version_id; version_id=$(konnect_get "/v3/apis/$api_id/versions" | jq -r '.data[0].id // empty')
  if [ -z "$version_id" ]; then
    konnect_post "/v3/apis/$api_id/versions" \
      "{\"spec\":{\"content\":$spec_json_escaped}}" > /dev/null
    log "  created version + spec"
  else
    konnect_patch "/v3/apis/$api_id/versions/$version_id" \
      "{\"spec\":{\"content\":$spec_json_escaped}}" > /dev/null
    log "  updated spec"
  fi
}

upsert_documents() {
  local api_id="$1" md_dir="$2"
  [ -d "$md_dir" ] || return 0

  local existing; existing=$(konnect_get "/v3/apis/$api_id/documents")

  for md_file in "$md_dir"/*.md; do
    [ -f "$md_file" ] || continue
    local slug; slug=$(basename "$md_file" .md)
    local content; content=$(cat "$md_file")
    local title; title=$(grep -m1 '^# ' "$md_file" | sed 's/^# //; s/[[:space:]]*$//')
    [ -n "$title" ] || title="$slug"
    local content_escaped; content_escaped=$(printf '%s' "$content" | jq -Rs .)
    local title_escaped; title_escaped=$(printf '%s' "$title" | jq -Rs .)
    local payload="{\"title\":$title_escaped,\"slug\":\"$slug\",\"content\":$content_escaped,\"status\":\"published\"}"

    local doc_id; doc_id=$(echo "$existing" | jq -r ".data[] | select(.slug==\"$slug\") | .id // empty")
    if [ -z "$doc_id" ]; then
      konnect_post "/v3/apis/$api_id/documents" "$payload" > /dev/null
      log "  created doc: $slug"
    else
      konnect_patch "/v3/apis/$api_id/documents/$doc_id" "$payload" > /dev/null
      log "  updated doc: $slug"
    fi
  done

  while IFS= read -r row; do
    local doc_id; doc_id=$(echo "$row" | jq -r '.id')
    local doc_slug; doc_slug=$(echo "$row" | jq -r '.slug')
    if [ ! -f "$md_dir/${doc_slug}.md" ]; then
      konnect_delete "/v3/apis/$api_id/documents/$doc_id"
      log "  deleted doc: $doc_slug"
    fi
  done < <(echo "$existing" | jq -c '.data[]')
}

# Ensure the catalog entry has exactly one gateway implementation.
# Deletes stale ones; creates the desired one if missing.
# If cp/service not found, still cleans up any existing stale links.
link_gateway() {
  local api_id="$1" cp_name="$2" svc_name="$3"

  local cp_id; cp_id=$(cp_id_for "$cp_name")
  local svc_id=""
  local desired_impl_id=""

  if [ -n "$cp_id" ]; then
    svc_id=$(service_id_for "$cp_id" "$svc_name")
  fi

  local existing; existing=$(konnect_get "/v3/api-implementations?filter%5Bapi_id%5D=${api_id}")

  if [ -n "$svc_id" ]; then
    desired_impl_id=$(echo "$existing" | \
      jq -r ".data[] | select(.service.control_plane_id==\"$cp_id\" and .service.id==\"$svc_id\") | .id // empty")
  fi

  # Delete all implementations except the desired one
  while IFS= read -r row; do
    local rid; rid=$(echo "$row" | jq -r '.id')
    [ -n "$desired_impl_id" ] && [ "$rid" = "$desired_impl_id" ] && continue
    konnect_delete "/v3/apis/$api_id/implementations/$rid"
    log "  removed stale gateway link"
  done < <(echo "$existing" | jq -c '.data[]')

  if [ -z "$cp_id" ]; then
    log "  skipping gateway link: control plane '$cp_name' not found"
    return 0
  fi
  if [ -z "$svc_id" ]; then
    log "  skipping gateway link: service '$svc_name' not found in '$cp_name'"
    return 0
  fi

  if [ -z "$desired_impl_id" ]; then
    # A service can only be linked to one catalog entry. If it's on another entry
    # (e.g. old 'alice' before 'alice-dev' was introduced), migrate it here.
    local all_impls; all_impls=$(konnect_get "/v3/api-implementations")
    local conflict; conflict=$(echo "$all_impls" | jq -c \
      "first(.data[] | select(.service.control_plane_id==\"$cp_id\" and .service.id==\"$svc_id\" and .api_id!=\"$api_id\"))" \
      2>/dev/null || echo "null")
    if [ -n "$conflict" ] && [ "$conflict" != "null" ]; then
      local conf_api; conf_api=$(echo "$conflict" | jq -r '.api_id')
      local conf_impl; conf_impl=$(echo "$conflict" | jq -r '.id')
      konnect_delete "/v3/apis/$conf_api/implementations/$conf_impl"
      log "  migrated gateway link from previous entry"
    fi
    konnect_post "/v3/apis/$api_id/implementations" \
      "{\"service\":{\"control_plane_id\":\"$cp_id\",\"id\":\"$svc_id\"}}" > /dev/null
    log "  linked gateway: $cp_name / $svc_name"
  else
    log "  gateway already linked: $cp_name / $svc_name"
  fi
}

publish_to_portal() {
  local api_id="$1" portal_id="$2" portal_name="$3"
  konnect_put "/v3/apis/$api_id/publications/$portal_id" '{}' > /dev/null
  log "  published to portal: $portal_name"
}

# ---------- main loop -------------------------------------------------------

for APP in $APPS_LIST; do
  CFG="apis/$APP/konnect.yaml"
  [ -f "$CFG" ] || continue

  enabled=$(grep -E '^catalog:' "$CFG" | awk '{print $2}')
  [ "$enabled" = "true" ] || continue

  SPEC="apis/$APP/openapi-spec/openapi-spec.yaml"
  MD_DIR="apis/$APP/md-files"

  # One catalog entry per gateway, named by convention:
  #   control plane name contains "dev"  → {app}-dev, matched to portals containing "dev"
  #   control plane name contains "prod" → {app},     matched to portals containing "prod"
  while IFS=: read -r cp_name svc_name; do
    [ -n "$cp_name" ] || continue

    if echo "$cp_name" | grep -q 'dev'; then
      CATALOG_NAME="${APP}-dev"
      ENV_KEYWORD="dev"
    else
      CATALOG_NAME="${APP}"
      ENV_KEYWORD="prod"
    fi

    log "Publishing $APP → $CATALOG_NAME"

    API_ID=$(upsert_api "$CATALOG_NAME" "$CATALOG_NAME API")
    upsert_version "$API_ID" "$SPEC"
    upsert_documents "$API_ID" "$MD_DIR"
    link_gateway "$API_ID" "$cp_name" "$svc_name"

    while IFS= read -r portal_name; do
      [ -n "$portal_name" ] || continue
      echo "$portal_name" | grep -q "$ENV_KEYWORD" || continue
      PORTAL_ID=$(portal_id_for "$portal_name")
      publish_to_portal "$API_ID" "$PORTAL_ID" "$portal_name"
    done < <(awk '
      /^portals:/ { in_p=1; next }
      /^[^ ]/     { in_p=0 }
      in_p && /^[[:space:]]+-[[:space:]]+[^:]/ { print $2 }
    ' "$CFG")

    ok "$CATALOG_NAME published"
  done < <(awk '
    /^gateways:/ { in_gw=1; next }
    /^[^ ]/       { in_gw=0 }
    in_gw && /control_plane:/ { cp=$NF }
    in_gw && /service:/        { print cp ":" $NF }
  ' "$CFG")
done
