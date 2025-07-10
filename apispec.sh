#!/bin/bash

# Variables
TOKEN=""
ORG_ID="1b2f5a87-d65a-4d30-8a97-3a4b788e3178"
API_NAME="bob"
API_VERSION="v1"
SPEC_FILE="apis/bob/openapi-spec/openapi-spec.yaml"
API_HOST="https://eu.api.konghq.com"
SLUG=$(echo "${API_NAME}-${API_VERSION}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
ENVIRONMENT="test"

# Read file content into a JSON-safe string
SPEC_CONTENT=$(<"$SPEC_FILE" yq -o=json | jq -Rs .)

# Get existing API if present
RESPONSE=$(curl -s -G "$API_HOST/v3/apis" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "filter[name]=$API_NAME" \
  --data-urlencode "filter[version]=$API_VERSION")

echo "$RESPONSE" | jq .

# Check if API exists
API_EXISTS=$(echo "$RESPONSE" | jq -r '.data | length')

if [ "$API_EXISTS" -gt 0 ]; then
  EXISTING_API_ID=$(echo "$RESPONSE" | jq -r '.data[0].id')
  EXISTING_SPEC_ID=$(echo "$RESPONSE" | jq -r '.data[0].api_spec_ids[0]')
  echo "Found existing API:"
  echo "  ID: $EXISTING_API_ID"
  echo "  Spec ID: $EXISTING_SPEC_ID"

  echo "Updating existing API $EXISTING_API_ID..."
  curl -s --request PATCH \
    --url "$API_HOST/v3/apis/$EXISTING_API_ID/versions/$EXISTING_SPEC_ID" \
    --header "Accept: application/json, application/problem+json" \
    --header "Authorization: Bearer $TOKEN" \
    --header "Content-Type: application/json" \
    --data "{
      \"spec\": {
        \"content\": $SPEC_CONTENT
      }
    }" | jq .
else
  echo "No existing API found. Creating new API..."
  curl -s -X POST "$API_HOST/v3/apis" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data "{
      \"name\": \"$API_NAME\",
      \"version\": \"$API_VERSION\",
      \"slug\": \"$SLUG\",
      \"labels\": {\"env\": \"$ENVIRONMENT\"},
      \"spec_content\": $SPEC_CONTENT
    }" | jq .
fi
