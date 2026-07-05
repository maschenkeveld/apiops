#!/usr/bin/env bash
# Local convenience wrapper: publish one API to the Konnect API Catalog.
# Reads portal/gateway config from apis/$APP/konnect.yaml.
source "$(dirname "$0")/lib.sh"

APP="${1:?usage: publish-apis.sh <app>}"
require_env KONNECT_TOKEN

APPS_LIST="$APP" bash scripts/publish-api.sh

ok "Published: $APP"
