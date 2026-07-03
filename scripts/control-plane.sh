#!/usr/bin/env bash
# Print the Konnect control plane name for a logical environment (development|production).
# Used by workflows so the env→control-plane mapping lives in one place (lib.sh:cp_for_env).
source "$(dirname "$0")/lib.sh"
cp_for_env "${1:?usage: control-plane.sh <environment>}"
