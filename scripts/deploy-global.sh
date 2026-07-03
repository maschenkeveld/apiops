#!/usr/bin/env bash
# Deploy global Konnect components (consumers, consumer groups, plugins, redis) to a control plane.
# Per component: patch the deck file, diff, then sync scoped with --select-tag <component>.
# Set DRY_RUN=1 to diff only.
#
# Usage:
#   deploy-global.sh <control-plane> <component>     # one component (CI matrix calls this)
#   deploy-global.sh <control-plane>                 # all components, in dependency order
source "$(dirname "$0")/lib.sh"

CP="${1:?usage: deploy-global.sh <control-plane> [component]}"
require_env KONNECT_TOKEN

# Order matters: consumers depend on consumer groups; plugins may depend on both.
DEFAULT_COMPONENTS=(global-consumer-groups global-consumers global-plugins global-redis)
if [ "${2:-}" != "" ]; then
  COMPONENTS=("$2")
else
  COMPONENTS=("${DEFAULT_COMPONENTS[@]}")
fi

# Resolve ${{ env "..." }} in patches against the control plane's global env-vars, if present.
# shellcheck disable=SC1090
[ -f "global/env-vars/$CP" ] && source "global/env-vars/$CP"

mkdir -p global/deck-file/generated

for c in "${COMPONENTS[@]}"; do
  config="global/deck-file/$c.yaml"
  patch="global/patches/$c.yaml"
  out="global/deck-file/generated/$c-patched.yaml"
  [ -f "$config" ] || die "config not found: $config"
  [ -f "$patch" ]  || die "patch not found: $patch"

  log "Patch $c → $out"
  deck file patch -s "$config" "$patch" > "$out"

  log "deck gateway diff: $c → $CP"
  deck gateway diff "$out" \
    --konnect-addr "$KONNECT_ADDR" \
    --konnect-control-plane-name "$CP" \
    --konnect-token "$KONNECT_TOKEN" \
    --select-tag "$c" || true

  if [ "${DRY_RUN:-0}" = "1" ]; then
    ok "Dry run (diff only): $c"
    continue
  fi

  log "deck gateway sync: $c → $CP"
  deck gateway sync "$out" \
    --konnect-addr "$KONNECT_ADDR" \
    --konnect-control-plane-name "$CP" \
    --konnect-token "$KONNECT_TOKEN" \
    --select-tag "$c"
  ok "Deployed $c"
done
