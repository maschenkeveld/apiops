#!/usr/bin/env bash
# Generate a self-contained HTML documentation page for one API's OpenAPI spec (Redocly build-docs).
# Prints the output HTML path on stdout.
#
# Usage: docs.sh <app> [output.html]
source "$(dirname "$0")/lib.sh"

APP="${1:?usage: docs.sh <app> [output.html]}"
OUT="${2:-apis/$APP/openapi-spec/openapi-spec-bundled.html}"
SPEC="apis/$APP/openapi-spec/openapi-spec.yaml"
[ -f "$SPEC" ] || die "spec not found: $SPEC"

log "Generate HTML docs: $APP → $OUT"
redocly build-docs "$SPEC" -o "$OUT"
ok "Docs built: $APP"
echo "$OUT"
