#!/usr/bin/env bash
# Generate the Kong deck file for one API: bundle -> openapi2kong -> merge/add-plugins/
# patch/add-tags/namespace. Single source of truth for deck generation, shared by the
# local runner and the generate-kong-config composite action in CI.
#
# Env vars are intentionally NOT sourced here: the patches use deck's
# `${{ env "DECK_*" }}` templating, which is resolved later at `deck gateway sync`.
source "$(dirname "$0")/lib.sh"

APP="${1:?usage: generate.sh <app>}"
log "Generate deck config: $APP"

redocly bundle "apis/$APP/openapi-spec/openapi-spec.yaml" \
  -o "apis/$APP/openapi-spec/openapi-spec-bundled.yaml"

deck file openapi2kong -s "apis/$APP/openapi-spec/openapi-spec-bundled.yaml" \
  > "apis/$APP/deck-file/generated/kong-generated.yaml"

VER="$(major_version "$APP")"

deck file merge "apis/$APP/deck-file/generated/kong-generated.yaml" "apis/$APP/additions/additions.yaml" \
  | deck file add-plugins "apis/$APP/plugins/plugins.yaml" \
  | deck file patch shared/patches/deck.yaml \
  | deck file patch "apis/$APP/patches/deck.yaml" \
  | deck file add-tags "$APP" \
  | deck file add-tags "$VER" \
  | deck file namespace --path-prefix="/$APP/$VER" \
  > "apis/$APP/deck-file/generated/kong-plugined-and-patched.yaml"

ok "Generated apis/$APP/deck-file/generated/kong-plugined-and-patched.yaml ($VER)"
