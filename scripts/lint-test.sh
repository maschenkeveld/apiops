#!/usr/bin/env bash
# Prove the deck lint ruleset does what it claims: shared/deck-linting/tests/good.yaml must pass,
# every bad-*.yaml must FAIL. No Konnect access needed.
source "$(dirname "$0")/lib.sh"

RULESET="shared/deck-linting/ruleset.yaml"
DIR="shared/deck-linting/tests"
failed=0

lint() { deck file lint "$RULESET" --state "$1" --fail-severity error >"$2" 2>&1; }
crashed() { grep -qE 'panic:|goroutine [0-9]+' "$1"; }

out="$(mktemp)"; trap 'rm -f "$out"' EXIT

log "good.yaml must pass"
if lint "$DIR/good.yaml" "$out" && ! crashed "$out"; then ok "good.yaml passed"; else cat "$out" >&2; log "FAIL: good.yaml was rejected"; failed=1; fi

for f in "$DIR"/bad-*.yaml; do
  log "$(basename "$f") must be rejected"
  if lint "$f" "$out"; then
    log "FAIL: $(basename "$f") was accepted"; failed=1
  elif crashed "$out" || ! grep -q '\[error\]' "$out"; then
    # A crash or a non-lint error is not a rejection by the ruleset.
    cat "$out" >&2; log "FAIL: $(basename "$f") failed without a lint violation (deck $(deck version | head -1))"; failed=1
  else
    ok "$(basename "$f") rejected: $(grep -m1 '\[error\]' "$out" | cut -c1-110)"
  fi
done

[ "$failed" = 0 ] || die "deck lint tests failed"
ok "deck lint tests passed"
