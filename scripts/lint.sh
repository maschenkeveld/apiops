#!/usr/bin/env bash
# Lint the built deck config against the shared ruleset (blocking on errors).
# Shared by the local runner and lint-deck.yaml in CI.
source "$(dirname "$0")/lib.sh"

APP="${1:?usage: lint.sh <app>}"
FILE="apis/$APP/deck-file/generated/kong-plugined-and-patched.yaml"
[ -f "$FILE" ] || die "built config missing — run build.sh first: $FILE"

log "Lint deck config: $APP"
deck file lint --ruleset shared/deck-linting/ruleset.yaml "$FILE" --fail-severity error
ok "Lint passed: $APP"
