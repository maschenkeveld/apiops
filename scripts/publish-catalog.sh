#!/usr/bin/env bash
# Publishes APIs to the Konnect API Catalog and developer portals.
# Which APIs and portals to target is driven by apis/$APP/konnect.yaml:
#
#   catalog: true
#   portals:
#     - apiops-developer-portal
#
# All IDs are resolved by name at runtime — nothing hardcoded.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

: "${KONNECT_TOKEN:?KONNECT_TOKEN must be set}"
: "${APPS_LIST:?APPS_LIST must be set}"
: "${KONNECT_REGION:=eu}"

BASE_URL="https://${KONNECT_REGION}.api.konghq.com"
AUTH=(-H "Authorization: Bearer $KONNECT_TOKEN" -H "Content-Type: application/json")

# ---------- helpers --------------------------------------------------------

konnect_get()  { curl -sf "$BASE_URL$1" "${AUTH[@]}"; }
konnect_post() { curl -sf -X POST  "$BASE_URL$1" "${AUTH[@]}" -d "$2"; }
konnect_put()  { curl -sf -X PUT   "$BASE_URL$1" "${AUTH[@]}" -d "$2"; }
konnect_patch(){ curl -sf -X PATCH "$BASE_URL$1" "${AUTH[@]}" -d "$2"; }
konnect_delete(){ curl -sf -X DELETE "$BASE_URL$1" "${AUTH[@]}"; }

jq_r() { echo "$1" | jq -r "$2"; }

# Resolve portal name → ID
portal_id_for() {
  local name="$1"
  local encoded; encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))")
  local id; id=$(konnect_get "/v3/portals?filter%5Bname%5D=${encoded}" \
    | jq -r '.data[0].id // empty')
  [ -n "$id" ] || die "portal not found: $name"
  echo "$id"
}

# Get or create an API by name; echoes its ID
upsert_api() {
  local name="$1" desc="$2"
  local id; id=$(konnect_get "/v3/apis?filter%5Bname%5D=${name}" | jq -r '.data[0].id // empty')
  if [ -z "$id" ]; then
    id=$(konnect_post "/v3/apis" "{\"name\":\"$name\",\"description\":\"$desc\"}" | jq -r '.id')
    log "  created API: $name"
  fi
  echo "$id"
}

# Upsert the OAS version+spec for an API
upsert_version() {
  local api_id="$1" spec_file="$2"
  local spec_json; spec_json=$(python3 -c \
    "import yaml,json,sys; print(json.dumps(yaml.safe_load(open('$spec_file'))))" 2>/dev/null \
    || yq -o=json . "$spec_file")
  local spec_json_escaped; spec_json_escaped=$(echo "$spec_json" | jq -Rs .)

  # Check if a version already exists
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

# Sync markdown files from a directory to API documents
# Creates new, updates changed, deletes removed
upsert_documents() {
  local api_id="$1" md_dir="$2"
  [ -d "$md_dir" ] || return 0

  # Fetch existing documents (slug → id map)
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

  # Delete documents not backed by an md file
  while IFS= read -r row; do
    local doc_id; doc_id=$(echo "$row" | jq -r '.id')
    local doc_slug; doc_slug=$(echo "$row" | jq -r '.slug')
    if [ ! -f "$md_dir/${doc_slug}.md" ]; then
      konnect_delete "/v3/apis/$api_id/documents/$doc_id"
      log "  deleted doc: $doc_slug"
    fi
  done < <(echo "$existing" | jq -c '.data[]')
}

# Publish an API to a portal by portal ID (idempotent PUT)
publish_to_portal() {
  local api_id="$1" portal_id="$2" portal_name="$3"
  konnect_put "/v3/apis/$api_id/publications/$portal_id" '{}' > /dev/null
  log "  published to portal: $portal_name"
}

# Resolve control plane name → ID; empty string if not found
cp_id_for() {
  local name="$1"
  local encoded; encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))")
  konnect_get "/v2/control-planes?filter%5Bname%5D=${encoded}" | jq -r '.data[0].id // empty'
}

# Resolve service name → ID within a control plane; empty if not found
service_id_for() {
  local cp_id="$1" name="$2"
  konnect_get "/v2/control-planes/$cp_id/core-entities/services" | \
    jq -r ".data[] | select(.name==\"$name\") | .id" | head -1
}

# Sync gateway service implementations for an API.
# Creates links that are missing; deletes links no longer declared.
# Skips silently when the control plane or service doesn't exist yet.
upsert_implementations() {
  local api_id="$1" cfg="$2"

  [ -f "$cfg" ] || return 0
  grep -q '^gateways:' "$cfg" || return 0

  # Parse gateways list from YAML as "cp_name:svc_name" pairs, one per line.
  # Works on the fixed structure: gateways: / - control_plane: X / service: Y
  local pairs; pairs=$(awk '
    /^gateways:/ { in_gw=1; next }
    /^[^ ]/       { in_gw=0 }
    in_gw && /control_plane:/ { cp=$NF }
    in_gw && /service:/        { print cp ":" $NF }
  ' "$cfg")

  [ -n "$pairs" ] || return 0

  local existing; existing=$(konnect_get "/v3/api-implementations?filter%5Bapi_id%5D=${api_id}")

  # Track desired cp+svc IDs to detect stale links later
  local desired_pairs=""

  while IFS=: read -r cp_name svc_name; do
    [ -n "$cp_name" ] || continue

    local cp_id; cp_id=$(cp_id_for "$cp_name")
    if [ -z "$cp_id" ]; then
      log "  skipping gateway link: control plane '$cp_name' not found"
      continue
    fi

    local svc_id; svc_id=$(service_id_for "$cp_id" "$svc_name")
    if [ -z "$svc_id" ]; then
      log "  skipping gateway link: service '$svc_name' not found in '$cp_name'"
      continue
    fi

    desired_pairs="${desired_pairs}${cp_id}:${svc_id}"$'\n'

    local impl_id; impl_id=$(echo "$existing" | \
      jq -r ".data[] | select(.service.control_plane_id==\"$cp_id\" and .service.id==\"$svc_id\") | .id // empty")
    if [ -z "$impl_id" ]; then
      konnect_post "/v3/apis/$api_id/implementations" \
        "{\"service\":{\"control_plane_id\":\"$cp_id\",\"id\":\"$svc_id\"}}" > /dev/null
      log "  linked gateway: $cp_name / $svc_name"
    else
      log "  gateway already linked: $cp_name / $svc_name"
    fi
  done <<< "$pairs"

  # Delete implementations no longer declared
  while IFS= read -r row; do
    local impl_id; impl_id=$(echo "$row" | jq -r '.id')
    local impl_cp;  impl_cp=$(echo "$row" | jq -r '.service.control_plane_id')
    local impl_svc; impl_svc=$(echo "$row" | jq -r '.service.id')
    if ! echo "$desired_pairs" | grep -qF "${impl_cp}:${impl_svc}"; then
      konnect_delete "/v3/apis/$api_id/implementations/$impl_id"
      log "  removed stale gateway link: $impl_cp / $impl_svc"
    fi
  done < <(echo "$existing" | jq -c '.data[]')
}

# ---------- main loop -------------------------------------------------------

for APP in $APPS_LIST; do
  CFG="apis/$APP/konnect.yaml"
  [ -f "$CFG" ] || continue

  enabled=$(grep -E '^catalog:' "$CFG" | awk '{print $2}')
  [ "$enabled" = "true" ] || continue

  log "Publishing $APP to catalog"

  SPEC="apis/$APP/openapi-spec/openapi-spec.yaml"
  MD_DIR="apis/$APP/md-files"
  DESC=$(grep -m1 '^title:' "$SPEC" | awk '{print $2}' || echo "$APP")

  API_ID=$(upsert_api "$APP" "$APP API")
  upsert_version "$API_ID" "$SPEC"
  upsert_documents "$API_ID" "$MD_DIR"
  upsert_implementations "$API_ID" "$CFG"

  # Publish to portals listed in konnect.yaml
  while IFS= read -r portal_name; do
    [ -n "$portal_name" ] || continue
    PORTAL_ID=$(portal_id_for "$portal_name")
    publish_to_portal "$API_ID" "$PORTAL_ID" "$portal_name"
  done < <(awk '
    /^portals:/ { in_p=1; next }
    /^[^ ]/     { in_p=0 }
    in_p && /^[[:space:]]+-[[:space:]]+[^:]/ { print $2 }
  ' "$CFG")

  ok "$APP published"
done
