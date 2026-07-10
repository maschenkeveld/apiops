#!/usr/bin/env bash
# End-to-end local demo: for each app, validate → build → lint → deploy, then verify
# the control plane once and publish each app to the Dev Portal.
#
# Usage: demo.sh <control-plane> <app> [app...]
# Requires: KONNECT_TOKEN (deploy/verify/publish) and PORTAL_ID (publish).
# Set DRY_RUN=1 to diff instead of sync (and skip publish).
source "$(dirname "$0")/lib.sh"

CP="${1:?usage: demo.sh <control-plane> <app> [app...]}"
shift
[ "$#" -ge 1 ] || die "provide at least one app, e.g. demo.sh apiops-development alice"

HERE="$(cd "$(dirname "$0")" && pwd)"

for APP in "$@"; do
  printf '\n\033[1;35m===== %s =====\033[0m\n' "$APP"
  "$HERE/validate.sh" "$APP"
  "$HERE/generate.sh" "$APP"
  "$HERE/lint.sh" "$APP"
  "$HERE/deploy.sh" "$APP" "$CP"
done

"$HERE/verify.sh" "$CP"

if [ "${DRY_RUN:-0}" = "1" ]; then
  ok "Demo (dry run) complete: $CP [$*]"
  exit 0
fi

require_env PORTAL_ID
for APP in "$@"; do
  "$HERE/publish.sh" "$APP" "$CP"
done

ok "Demo complete: $CP [$*]"
