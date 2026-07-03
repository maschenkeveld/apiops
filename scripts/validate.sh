#!/usr/bin/env bash
# Validate one API's OpenAPI spec — the same checks as validate-apis.yaml:
#   1. Spectral lint (httpbin is a third-party spec, exempt)
#   2. When the bundled spec changed vs the base branch:
#      - changelog.md last line version matches the spec version
#      - version was incremented and is valid semver
#      - oasdiff breaking changes are registered in breaking-changes.yaml
#
# The baseline is taken from git (BASE_REF, default origin/main) via a temporary worktree so
# $refs resolve. If no baseline is available (shallow checkout / no origin/main / not a git repo),
# the change-gated checks are skipped with a warning and only Spectral runs.
source "$(dirname "$0")/lib.sh"

APP="${1:?usage: validate.sh <app>}"
BASE_REF="${BASE_REF:-origin/main}"
SPEC="apis/$APP/openapi-spec/openapi-spec.yaml"
[ -f "$SPEC" ] || die "spec not found: $SPEC"

bundled="apis/$APP/openapi-spec/openapi-spec-bundled.yaml"
log "Validate OpenAPI: $APP"

# 1. Lint -------------------------------------------------------------------
redocly bundle "$SPEC" -o "$bundled"
if [ "$APP" != "httpbin" ]; then
  spectral lint "$bundled" --ruleset shared/.spectral.yaml --verbose
else
  log "Skipping Spectral for third-party spec: $APP"
fi

# 2. Baseline ---------------------------------------------------------------
git fetch -q origin "${BASE_REF#origin/}" 2>/dev/null || true
worktree="$(mktemp -d)"
if ! git worktree add -q --detach "$worktree" "$BASE_REF" 2>/dev/null; then
  rm -rf "$worktree"
  log "No baseline ($BASE_REF) available — skipping version/breaking checks"
  ok "OpenAPI valid: $APP (spectral only)"
  exit 0
fi
cleanup() { git worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"; }
trap cleanup EXIT

if [ ! -f "$worktree/$SPEC" ]; then
  log "API is new (not on $BASE_REF) — skipping version/breaking checks"
  ok "OpenAPI valid: $APP (new API)"
  exit 0
fi

base_bundled="apis/$APP/openapi-spec/openapi-spec-bundled-main.yaml"
redocly bundle "$worktree/$SPEC" -o "$base_bundled"

main_version="$(yq -r '.info.version' "$worktree/$SPEC" | tr -d '"')"
pr_version="$(yq -r '.info.version' "$SPEC" | tr -d '"')"

if diff -q "$bundled" "$base_bundled" >/dev/null 2>&1; then
  ok "OpenAPI valid: $APP (no spec change vs $BASE_REF)"
  exit 0
fi
log "Spec changed vs $BASE_REF (was $main_version, now $pr_version)"

# 3. changelog.md ----------------------------------------------------------
changelog="apis/$APP/changelog.md"
[ -f "$changelog" ] || die "changelog.md not found: $changelog"
changelog_version="$(tail -n 1 "$changelog" | cut -d':' -f1 | tr -d '[:space:]')"
[ "$pr_version" = "$changelog_version" ] \
  || die "changelog version mismatch: spec=$pr_version changelog=$changelog_version"

# 4. version increment + semver -------------------------------------------
[ "$pr_version" != "$main_version" ] \
  || die "version must be incremented when the spec changes (still $pr_version)"
semver='^[0-9]+\.[0-9]+(\.[0-9]+)?$'
[[ "$pr_version" =~ $semver ]]  || die "invalid semver: $pr_version"
[[ "$main_version" =~ $semver ]] || die "invalid semver (base): $main_version"
printf '%s\n%s\n' "$main_version" "$pr_version" | sort -V -C \
  || die "version not incremented: $main_version → $pr_version"

# 5. breaking changes ------------------------------------------------------
if ! command -v oasdiff >/dev/null 2>&1; then
  log "oasdiff not installed — skipping breaking-change check"
  ok "OpenAPI valid: $APP"
  exit 0
fi
breaking="$(oasdiff breaking "$base_bundled" "$bundled" 2>&1 || true)"
if echo "$breaking" | grep -qi "no breaking changes" || [ -z "$breaking" ]; then
  ok "OpenAPI valid: $APP (no breaking changes)"
  exit 0
fi

log "Breaking changes detected for $APP:"
echo "$breaking" >&2
bc_file="apis/$APP/breaking-changes.yaml"
[ -f "$bc_file" ] || die "breaking changes detected but $bc_file is missing — register version $pr_version"
if yq eval ".breaking_changes[] | select(.version == \"$pr_version\")" "$bc_file" | grep -q "version"; then
  reason="$(yq eval ".breaking_changes[] | select(.version == \"$pr_version\") | .reason" "$bc_file")"
  ok "Breaking changes approved for $pr_version: $reason"
else
  die "breaking changes for $pr_version not registered in $bc_file"
fi
