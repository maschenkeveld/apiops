# Using the Crawl Endpoint

The `/crawl` endpoint lets Alice recursively call a chain of upstream services and aggregate their responses. This is useful for tracing requests through the mesh and verifying end-to-end connectivity.

## Request Format

```json
{
  "upstreams": [
    {
      "host": "http://bob/crawl",
      "upstreams": [
        {
          "host": "http://alice/identify"
        }
      ]
    }
  ]
}
```

Each node in the tree is fetched in parallel; the response from each node is embedded in the parent's `upstreamResponses` array.

## Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  https://kong-proxy-dp-konnect-eu-apiops-development.schenkeveld.io/alice/v1/crawl \
  -d '{
    "upstreams": [
      { "host": "http://bob/identify" }
    ]
  }' | jq .
```

## Response Shape

```json
{
  "statusCode": 200,
  "name": "alice",
  "zone": "zone-eu-1",
  "reason": null,
  "incomingHeaders": { "x-consumer-username": "my-client" },
  "upstreamResponses": [
    {
      "statusCode": 200,
      "name": "bob",
      "zone": "zone-eu-1",
      "reason": null,
      "incomingHeaders": {},
      "upstreamResponses": []
    }
  ]
}
```

## Mesh Connectivity Testing

To verify that alice can reach every service in the mesh, crawl all neighbours in one shot:

```bash
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  .../alice/v1/crawl \
  -d '{
    "upstreams": [
      { "host": "http://bob/identify" },
      { "host": "http://alice/identify" }
    ]
  }'
```

A `statusCode: 200` for every node confirms the mesh policies are in place and mTLS is working.
