#!/bin/bash

# Variables
TOKEN="kpat_"                                                                      # SHOULD COME FROM A SECRET
ORG_ID=""                                                                   # THIS IS A FIXED VALUE
PORTAL_ID=""                                                                     # HERE WE WILL NEED THE PORTAL ID WHERE THE API WILL BE PUBLISHED 
API_HOST="https://eu.api.konghq.com"                                                        # THIS IS A FIXED VALUE
API_NAME="alice"                                                                              # FOP WHICH API DO YOU WANT TO RUN THE PIPELINE            
API_VERSION="v1"                                                                            # THIS SHOULD COME FROM THE OPENAPI SPEC AND/OR THE FOLDER NAME

ENVIRONMENT="apiops-development"                                                          # THIS SHOULD COME FROM THE ENVIRONMENT WHERE THE API WILL BE PUBLISHED

OAS_SPEC_FILE="apis/$API_NAME/openapi-spec/openapi-spec.yaml"
API_SLUG=$(echo "${API_NAME}-${API_VERSION}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
OAS_SPEC_CONTENT=$(<"$OAS_SPEC_FILE" yq -o=json | jq -Rs .)


# --- CREATE OR UPDATE API AND UPLOAD API SPECIFICATION ---

# GET EXISTING API IF PRESENT
APIS_RESPONSE=$(curl -s -G "$API_HOST/v3/apis" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "filter[name]=$API_NAME" \
  --data-urlencode "filter[version]=$API_VERSION")

# echo "$APIS_RESPONSE" | jq .

# CHECK IF API EXISTS
API_EXISTS=$(echo "$APIS_RESPONSE" | jq -r '.data | length')

# UPDATE OR CREATE API
if [ "$API_EXISTS" -gt 0 ]; then
  EXISTING_API_ID=$(echo "$APIS_RESPONSE" | jq -r '.data[0].id')
  EXISTING_SPEC_ID=$(echo "$APIS_RESPONSE" | jq -r '.data[0].api_spec_ids[0]')
  echo "Found existing API:"
  echo "✅ ID: $EXISTING_API_ID"
  echo "✅ Spec ID: $EXISTING_SPEC_ID"

  echo "Updating existing API $EXISTING_API_ID..."
  UPDATE_API_RESPONSE=$(curl -s --request PATCH \
    --url "$API_HOST/v3/apis/$EXISTING_API_ID/versions/$EXISTING_SPEC_ID" \
    --header "Accept: application/json, application/problem+json" \
    --header "Authorization: Bearer $TOKEN" \
    --header "Content-Type: application/json" \
    --data "{
      \"spec\": {
        \"content\": $OAS_SPEC_CONTENT
      }
    }" | jq .)
else
  echo "No existing API found. Creating new API..."
  CREATE_API_RESPONSE=$(curl -s -X POST "$API_HOST/v3/apis" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data "{
      \"name\": \"$API_NAME\",
      \"version\": \"$API_VERSION\",
      \"slug\": \"$API_SLUG\",
      \"labels\": {\"env\": \"$ENVIRONMENT\"},
      \"spec_content\": $OAS_SPEC_CONTENT
    }" | jq .)
fi

# --- UPLOAD API DOCUMENTATION ---

MD_DIR="apis/$API_NAME/md-files"

# CHECK FOR MARKDOWN FILES
for MD_FILE in "$MD_DIR"/*.md; do
  [ -e "$MD_FILE" ] || continue  # skip if no files match

  # Extract base filename (e.g., "intro.md")
  FILE_NAME=$(basename "$MD_FILE")
  BASE_NAME="${FILE_NAME%.*}" # "intro"

  # Convert to Title Case (e.g., "Intro")
  # DOC_TITLE=$(echo "$BASE_NAME" | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g') # CAN BE DONE USING SED
  DOC_TITLE=$(echo "$BASE_NAME" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1') # OR USING AWK

  
  # Convert to slug (e.g., "intro-section" from "Intro Section")
  DOC_SLUG=$(echo "$BASE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

  echo "Processing: $MD_FILE → Title: $DOC_TITLE, Slug: $DOC_SLUG"

  MD_CONTENT=$(jq -Rs . < "$MD_FILE")

  # Get existing documents on this API
  DOCS_RESPONSE=$(curl -s -X GET "$API_HOST/v3/apis/$EXISTING_API_ID/documents" \
    -H "Authorization: Bearer $TOKEN")

  # Look for a document with the same slug
  EXISTING_DOC_ID=$(echo "$DOCS_RESPONSE" | jq -r --arg SLUG "$DOC_SLUG" '.data[] | select(.slug == $SLUG) | .id')

  if [ -n "$EXISTING_DOC_ID" ]; then
    echo "➡️ Updating existing document: $DOC_SLUG"

    UPDATE_DOC_RESPONSE=$(curl -s -X PATCH "$API_HOST/v3/apis/$EXISTING_API_ID/documents/$EXISTING_DOC_ID" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "{
        \"title\": \"$DOC_TITLE\",
        \"slug\": \"$DOC_SLUG\",
        \"content\": $MD_CONTENT,
        \"status\": \"published\"
      }" | jq .)
  else
    echo "➡️ Creating new document: $DOC_SLUG"

    CREATE_DOC_RESPONSE=$(curl -s -X POST "$API_HOST/v3/apis/$EXISTING_API_ID/documents" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "{
        \"title\": \"$DOC_TITLE\",
        \"slug\": \"$DOC_SLUG\",
        \"content\": $MD_CONTENT,
        \"status\": \"published\"
      }" | jq .)
  fi
done

# --- PUBLISH API TO PORTAL ---

# GET EXISTING API IF PRESENT, WE NEED TO DO THIS AGAIN TO GET THE API ID
APIS_RESPONSE=$(curl -s -G "$API_HOST/v3/apis" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "filter[name]=$API_NAME" \
  --data-urlencode "filter[version]=$API_VERSION")

# echo "$APIS_RESPONSE" | jq .

API_EXISTS=$(echo "$APIS_RESPONSE" | jq -r '.data | length')

API_ID=$(echo "$APIS_RESPONSE" | jq -r '.data[0].id')
SPEC_ID=$(echo "$APIS_RESPONSE" | jq -r '.data[0].api_spec_ids[0]')
echo "Found existing API:"
echo "✅ ID: $API_ID"
echo "✅ Spec ID: $SPEC_ID"

PUBLISH_API_RESPONSE=$(curl -X PUT "$API_HOST/v3/apis/$API_ID/publications/$PORTAL_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "visibility": "public",
    "auto_approve_registrations": true,
    "auth_strategy_ids": null
  }')

# --- LINK API TO RUNNING KONG GATEWAY SERVICE ---

CP_RESPONSE=$(curl -s -X GET "$API_HOST/v2/control-planes" \
  -H "Authorization: Bearer $TOKEN")

# echo "$CP_RESPONSE" | jq .

CP_ID=$(echo "$CP_RESPONSE" | jq -r ".data[] | select(.name == \"$ENVIRONMENT\") | .id")

if [ -z "$CP_ID" ]; then
  echo "❌ No control plane found for environment: $ENVIRONMENT"
  exit 1
fi

echo "✅ Found Control Plane ID: $CP_ID"

# Call Konnect API to get services
SERVICES_RESPONSE=$(curl -s -X GET "$API_HOST/v2/control-planes/$CP_ID/core-entities/services?tags=$API_NAME,$API_VERSION" \
  -H "Authorization: Bearer $TOKEN")

# echo "$SERVICES_RESPONSE" | jq .

# Extract the service ID matching both tags
SERVICE_ID=$(echo "$SERVICES_RESPONSE" | jq -r '.data[0].id')

if [ -z "$SERVICE_ID" ]; then
  echo "❌ No service found with tags: $API_NAME and $API_VERSION"
  exit 1
fi

echo "✅ Found Service ID: $SERVICE_ID"

# 1. GET api-implementations (paged)
IMPLEMENTATIONS_RESPONSE=$(curl -s --request GET "$API_HOST/v3/api-implementations" \
  -H "Accept: application/json, application/problem+json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json")

# 2. Check if service ID exists in any implementation
IMPLEMENTATION_EXISTS=$(echo "$IMPLEMENTATIONS_RESPONSE" | jq --arg service_id "$SERVICE_ID" '
  .data[] | select(.service.id == $service_id) | .id' | wc -l)

if [ "$IMPLEMENTATION_EXISTS" -gt 0 ]; then
  echo "✅ Implementation already exists for service ID: $SERVICE_ID"
else
  echo "⏳ Creating implementation..."

  IMPLEMENTATIONS_POST_RESPONSE=$(curl -s -X POST "https://us.api.konghq.com/v3/apis/$API_ID/implementations" \
    -H "Accept: application/json, application/problem+json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "service": {
    "control_plane_id": "$CP_ID",
    "id": "$SERVICE_ID"
  }
}
EOF
  )

  # echo "$POST_RESPONSE" | jq .
fi
