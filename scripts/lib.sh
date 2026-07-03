#!/usr/bin/env bash
# Shared helpers for the local pipeline scripts. Sourced by the others.
# Anchors the working directory at the repo root so every path is repo-relative,
# whether run inside the demo container (/work) or directly from a CI runner.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KONNECT_ADDR="${KONNECT_ADDR:-https://eu.api.konghq.com}"

# Logs go to stderr so scripts can return data on stdout (e.g. backup.sh prints the file path).
log() { printf '\033[1;34m▶ %s\033[0m\n' "$*" >&2; }
ok()  { printf '\033[1;32m✓ %s\033[0m\n' "$*" >&2; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Map a logical environment to its Konnect control plane name.
cp_for_env() {
  case "$1" in
    development) echo "apiops-development" ;;
    production)  echo "apiops-production" ;;
    *) die "invalid environment: '$1' (expected development|production)" ;;
  esac
}

require_env() {
  for v in "$@"; do
    [ -n "${!v:-}" ] || die "environment variable '$v' is required"
  done
}

# Major-version tag from the spec, e.g. "1.2.3" -> "v1". Matches deploy-apis.yaml.
major_version() {
  yq eval '.info.version | capture("^(?<m>\d+)") | "v\(.m)"' \
    "apis/$1/openapi-spec/openapi-spec.yaml"
}

# Source the shell env-var files for a control plane (shared + per-API), exactly
# like the deploy workflow does. Resolves the DECK_* vars referenced by patches.
load_env() {
  local cp="$1" app="$2"
  # shellcheck disable=SC1090
  [ -f "shared/env-vars/$cp" ] && source "shared/env-vars/$cp"
  # shellcheck disable=SC1090
  [ -f "apis/$app/env-vars/$cp" ] && source "apis/$app/env-vars/$cp"
}
