#!/usr/bin/env bash
# Publishes API catalog entries to Konnect via kongctl declarative sync.
# Generates a per-app catalog YAML at the repo root (so !file paths resolve),
# syncs with per-app namespace isolation, then removes the temp YAML.
#
# konnect.yaml format expected per app:
#   catalog:     true   — enable catalog publication
#   portal:      true   — enable dev portal publication (portal mode only)
#   development: true   — publish to apiops-development / apiops-developer-portal
#   production:  true   — publish to apiops-production  / apiops-production-portal
#
# PUBLISH_MODE:
#   catalog  — sync catalog entries + spec + implementations (no portal publications)
#   portal   — full sync including portal publications; respects per-app portal: flag
#              (defaults to portal for backwards compatibility when not set)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

: "${KONNECT_TOKEN:?KONNECT_TOKEN must be set}"
: "${APPS_LIST:?APPS_LIST must be set}"
: "${KONNECT_REGION:=eu}"
: "${PUBLISH_MODE:=portal}"

export KONGCTL_DEFAULT_KONNECT_PAT="$KONNECT_TOKEN"

BASE_URL="https://${KONNECT_REGION}.api.konghq.com"
AUTH=(-H "Authorization: Bearer $KONNECT_TOKEN" -H "Content-Type: application/json")

konnect_get()    { curl -sf "$BASE_URL$1" "${AUTH[@]}"; }
konnect_delete() { curl -sf -X DELETE "$BASE_URL$1" "${AUTH[@]}" || true; }

delete_api_if_exists() {
  local name="$1"
  local encoded; encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$name'))")
  local id; id=$(konnect_get "/v3/apis?filter%5Bname%5D=${encoded}" | jq -r '.data[0].id // empty')
  [ -n "$id" ] || return 0
  konnect_delete "/v3/apis/$id"
  log "  cleared existing entry: $name"
}

portal_id_for() {
  local name="$1"
  local encoded; encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$name'))")
  local id; id=$(konnect_get "/v3/portals?filter%5Bname%5D=${encoded}" | jq -r '.data[0].id // empty')
  [ -n "$id" ] || die "portal not found: $name"
  echo "$id"
}

cp_id_for() {
  local name="$1"
  local encoded; encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$name'))")
  konnect_get "/v2/control-planes?filter%5Bname%5D=${encoded}" | jq -r '.data[0].id // empty'
}

service_id_for() {
  local cp_id="$1" name="$2"
  konnect_get "/v2/control-planes/$cp_id/core-entities/services" | \
    jq -r ".data[] | select(.name==\"$name\") | .id" | head -1
}

md_title() {
  grep -m1 '^# ' "$1" 2>/dev/null | sed 's/^# //; s/[[:space:]]*$//' || echo "$2"
}

kv() { grep -E "^$1:" "$2" | awk '{print $2}'; }

declare -a TMPFILES=()
trap 'rm -f "${TMPFILES[@]}"' EXIT

for APP in $APPS_LIST; do
  CFG="apis/$APP/konnect.yaml"
  [ -f "$CFG" ] || continue

  [ "$(kv catalog "$CFG")" = "true" ] || continue

  if [ "$PUBLISH_MODE" = "portal" ]; then
    portal_flag=$(kv portal "$CFG")
    [ "${portal_flag:-true}" = "true" ] || { log "$APP: portal: false — skipping"; continue; }
  fi

  SPEC="apis/$APP/openapi-spec/openapi-spec.yaml"
  MD_DIR="apis/$APP/md-files"
  YAML_OUT="${APP}-catalog.yaml"
  TMPFILES+=("$YAML_OUT")

  SPEC_JSON=$(python3 -c \
    "import yaml,json,sys; d=yaml.safe_load(open(sys.argv[1])); print(json.dumps(d,separators=(',',':')))" \
    "$SPEC" 2>/dev/null || yq -o=json -I 0 . "$SPEC")
  SPEC_YAML_SAFE="${SPEC_JSON//\'/\'\'}"

  log "Generating $YAML_OUT (mode: $PUBLISH_MODE)"
  printf '_defaults:\n  kongctl:\n    namespace: %s\n\napis:\n' "$APP" > "$YAML_OUT"

  for ENV in development production; do
    [ "$(kv "$ENV" "$CFG")" = "true" ] || continue

    if [ "$ENV" = "development" ]; then
      CATALOG_NAME="${APP}-dev"
      CP_NAME="apiops-development"
      PORTAL_NAME="apiops-developer-portal"
    else
      CATALOG_NAME="${APP}"
      CP_NAME="apiops-production"
      PORTAL_NAME="apiops-production-portal"
    fi

    PORTAL_ID=""
    if [ "$PUBLISH_MODE" = "portal" ]; then
      PORTAL_ID=$(portal_id_for "$PORTAL_NAME")
    fi

    CP_ID=$(cp_id_for "$CP_NAME")
    SVC_ID=""
    [ -n "$CP_ID" ] && SVC_ID=$(service_id_for "$CP_ID" "$APP")

    delete_api_if_exists "$CATALOG_NAME"

    log "  $CATALOG_NAME → portal=${PORTAL_ID:-none} svc=${SVC_ID:-not linked}"

    cat >> "$YAML_OUT" <<ENTRY
  - ref: "${CATALOG_NAME}"
    name: "${CATALOG_NAME}"
    versions:
      - ref: "${CATALOG_NAME}-v1"
        version: "1.0.0"
        spec:
          content: '${SPEC_YAML_SAFE}'
ENTRY

    if [ "$PUBLISH_MODE" = "portal" ]; then
      cat >> "$YAML_OUT" <<PUB
    publications:
      - ref: "${CATALOG_NAME}-pub"
        portal_id: "${PORTAL_ID}"
        visibility: public
        auto_approve_registrations: false
PUB
    fi

    if [ -n "$SVC_ID" ]; then
      cat >> "$YAML_OUT" <<IMPL
    implementations:
      - ref: "${CATALOG_NAME}-impl"
        service:
          control_plane_id: "${CP_ID}"
          id: "${SVC_ID}"
IMPL
    fi

    if [ -d "$MD_DIR" ]; then
      printf '    documents:\n' >> "$YAML_OUT"
      for f in "$MD_DIR"/*.md; do
        [ -f "$f" ] || continue
        slug=$(basename "$f" .md)
        title=$(md_title "$f" "$slug")
        title="${title//\"/\\\"}"
        cat >> "$YAML_OUT" <<DOC
      - ref: "${CATALOG_NAME}-doc-${slug}"
        slug: "${slug}"
        title: "${title}"
        content: !file ${f}
        status: published
DOC
      done
    fi

  done

  kongctl sync konnect \
    -f "$YAML_OUT" \
    --base-dir . \
    --require-namespace "$APP" \
    --auto-approve \
    --region "$KONNECT_REGION"

  ok "$APP published (mode: $PUBLISH_MODE)"

done
