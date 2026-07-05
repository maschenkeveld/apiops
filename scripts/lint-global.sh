#!/usr/bin/env bash
# Lint the hand-written global deck files against the shared ruleset (blocking on errors).
source "$(dirname "$0")/lib.sh"

RULESET="shared/deck-linting/ruleset.yaml"
shopt -s nullglob
files=(global/deck-file/*.yaml)
if [ ${#files[@]} -eq 0 ]; then
  log "No global deck files to lint"
  exit 0
fi

for f in "${files[@]}"; do
  log "Lint global deck file: $f"
  deck file lint "$RULESET" --state "$f" --fail-severity error
done
ok "Global deck files lint passed"
