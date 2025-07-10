
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


MD_FILE="apis/bob/md-files/documentation.md"
DOC_TITLE="Documentation"
DOC_SLUG=$(echo "$DOC_TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

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

if [ -f "$MD_FILE" ]; then
  MD_CONTENT=$(jq -Rs . < "$MD_FILE")

  echo "Checking for existing documents on API $EXISTING_API_ID..."
  DOCS_RESPONSE=$(curl -s -X GET "$API_HOST/v3/apis/$EXISTING_API_ID/documents" \
    -H "Authorization: Bearer $TOKEN")

  # Try to find existing document by slug
  EXISTING_DOC_ID=$(echo "$DOCS_RESPONSE" | jq -r --arg SLUG "$DOC_SLUG" '.data[] | select(.slug == $SLUG) | .id')

  if [ -n "$EXISTING_DOC_ID" ]; then
    echo "Document '$DOC_SLUG' exists. Updating..."

    curl -s -X PATCH "$API_HOST/v3/apis/$EXISTING_API_ID/documents/$EXISTING_DOC_ID" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "{
        \"title\": \"$DOC_TITLE\",
        \"slug\": \"$DOC_SLUG\",
        \"content\": $MD_CONTENT,
        \"status\": \"published\"
        
      }" | jq .
  else
    echo "Document '$DOC_SLUG' does not exist. Creating new document..."

    curl -s -X POST "$API_HOST/v3/apis/$EXISTING_API_ID/documents" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "{
        \"title\": \"$DOC_TITLE\",
        \"slug\": \"$DOC_SLUG\",
        \"content\": $MD_CONTENT,
        \"status\": \"published\"
      }" | jq .
  fi
else
  echo "Markdown file not found: $MD_FILE"
fi
