
#!/bin/bash

# Variables
TOKEN=""
ORG_ID="1b2f5a87-d65a-4d30-8a97-3a4b788e3178"
API_NAME="bob"
API_VERSION="v1"
SPEC_FILE="apis/bob/openapi-spec/openapi-spec.yaml"
API_HOST="https://eu.api.konghq.com"
ENVIRONMENT="test"

PORTAL_ID="69a568c9-09b5-49aa-847a-3c057095e963"

# Get existing API if present
RESPONSE=$(curl -s -G "$API_HOST/v3/apis" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "filter[name]=$API_NAME" \
  --data-urlencode "filter[version]=$API_VERSION")

echo "$RESPONSE" | jq .

# Check if API exists
API_EXISTS=$(echo "$RESPONSE" | jq -r '.data | length')

EXISTING_API_ID=$(echo "$RESPONSE" | jq -r '.data[0].id')
EXISTING_SPEC_ID=$(echo "$RESPONSE" | jq -r '.data[0].api_spec_ids[0]')
echo "Found existing API:"
echo "  ID: $EXISTING_API_ID"
echo "  Spec ID: $EXISTING_SPEC_ID"

curl -X PUT "$API_HOST/v3/apis/$EXISTING_API_ID/publications/$PORTAL_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "visibility": "public",
    "auto_approve_registrations": true,
    "auth_strategy_ids": null
  }'
