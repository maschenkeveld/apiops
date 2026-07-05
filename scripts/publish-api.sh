#!/usr/bin/env bash
# Publishes API catalog entries to Konnect via kongctl declarative sync.
# Generates a per-app catalog YAML at the repo root (so !file paths resolve),
# syncs with per-app namespace isolation, then removes the temp YAML.
#
# konnect.yaml format expected per app:
#   catalog: true
#   portals:
#     - apiops-developer-portal     # contains "dev"  → matched to {app}-dev entry
#     - apiops-production-portal    # contains "prod" → matched to {app} entry
#   gateways:
#     - control_plane: apiops-development
#       service: alice
#     - control_plane: apiops-production
#       service: alice
set -euo pipefail
source "$(dirname "$0")/lib.sh"

: "${KONNECT_TOKEN:?KONNECT_TOKEN must be set}"
: "${APPS_LIST:?APPS_LIST must be set}"
: "${KONNECT_REGION:=eu}"

export KONGCTL_DEFAULT_KONNECT_PAT="$KONNECT_TOKEN"

BASE_URL="https://${KONNECT_REGION}.api.konghq.com"
AUTH=(-H "Authorization: Bearer $KONNECT_TOKEN" -H "Content-Type: application/json")

konnect_get() { curl -sf "$BASE_URL$1" "${AUTH[@]}"; }

portal_id_for() {
  local name="$1"
  local encoded; encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))")
  local id; id=$(konnect_get "/v3/portals?filter%5Bname%5D=${encoded}" | jq -r '.data[0].id // empty')
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

md_title() {
  grep -m1 '^# ' "$1" 2>/dev/null | sed 's/^# //; s/[[:space:]]*$//' || echo "$2"
}

declare -a TMPFILES=()
trap 'rm -f "${TMPFILES[@]}"' EXIT

for APP in $APPS_LIST; do
  CFG="apis/$APP/konnect.yaml"
  [ -f "$CFG" ] || continue

  enabled=$(grep -E '^catalog:' "$CFG" | awk '{print $2}')
  [ "$enabled" = "true" ] || continue

  SPEC="apis/$APP/openapi-spec/openapi-spec.yaml"
  MD_DIR="apis/$APP/md-files"
  YAML_OUT="${APP}-catalog.yaml"
  TMPFILES+=("$YAML_OUT")

  log "Generating $YAML_OUT"

  printf '_defaults:\n  kongctl:\n    namespace: %s\n\napis:\n' "$APP" > "$YAML_OUT"

  while IFS=: read -r cp_name svc_name; do
    [ -n "$cp_name" ] || continue

    if echo "$cp_name" | grep -q 'dev'; then
      CATALOG_NAME="${APP}-dev"
      ENV_KEYWORD="dev"
    else
      CATALOG_NAME="${APP}"
      ENV_KEYWORD="prod"
    fi

    # Resolve the matching portal ID
    PORTAL_ID=""
    while IFS= read -r pname; do
      [ -n "$pname" ] || continue
      echo "$pname" | grep -q "$ENV_KEYWORD" || continue
      PORTAL_ID=$(portal_id_for "$pname")
      break
    done < <(awk '
      /^portals:/ { in_p=1; next }
      /^[^ ]/     { in_p=0 }
      in_p && /^[[:space:]]+-[[:space:]]+[^:]/ { print $2 }
    ' "$CFG")

    if [ -z "$PORTAL_ID" ]; then
      log "  no $ENV_KEYWORD portal found, skipping $CATALOG_NAME"
      continue
    fi

    # Resolve CP and service IDs (service may not exist yet — link omitted if missing)
    CP_ID=$(cp_id_for "$cp_name")
    SVC_ID=""
    [ -n "$CP_ID" ] && SVC_ID=$(service_id_for "$CP_ID" "$svc_name")

    log "  $CATALOG_NAME → portal=$PORTAL_ID svc=${SVC_ID:-not linked}"

    cat >> "$YAML_OUT" <<ENTRY
  - ref: "${CATALOG_NAME}"
    name: "${CATALOG_NAME}"
    versions:
      - ref: "${CATALOG_NAME}-v1"
        version: "1.0.0"
        spec:
          content: !file ${SPEC}
    publications:
      - portal_id: "${PORTAL_ID}"
        visibility: public
        auto_approve_registrations: false
ENTRY

    if [ -n "$SVC_ID" ]; then
      cat >> "$YAML_OUT" <<IMPL
    implementations:
      - service:
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
      - slug: "${slug}"
        title: "${title}"
        content: !file ${f}
        status: published
DOC
      done
    fi

  done < <(awk '
    /^gateways:/ { in_gw=1; next }
    /^[^ ]/       { in_gw=0 }
    in_gw && /control_plane:/ { cp=$NF }
    in_gw && /service:/        { print cp ":" $NF }
  ' "$CFG")

  kongctl sync konnect \
    -f "$YAML_OUT" \
    --base-dir . \
    --require-namespace "$APP" \
    --auto-approve \
    --region "$KONNECT_REGION"

  ok "$APP published via kongctl"

done
