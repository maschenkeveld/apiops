# Using the Crawl Endpoint

The `/crawl` endpoint makes bob reach out to one or more upstream services and return their responses aggregated into a single tree. This mirrors the same endpoint on alice and is the primary tool for testing mesh-wide connectivity.

## Request Format

```json
{
  "upstreams": [
    {
      "host": "http://alice/crawl",
      "upstreams": [
        {
          "host": "http://bob/identify"
        }
      ]
    }
  ]
}
```

## Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  https://kong-proxy-dp-konnect-eu-apiops-development.schenkeveld.io/bob/v1/crawl \
  -d '{
    "upstreams": [
      { "host": "http://alice/identify" }
    ]
  }' | jq .
```

## Response Shape

```json
{
  "statusCode": 200,
  "name": "bob",
  "zone": "zone-eu-1",
  "reason": null,
  "incomingHeaders": { "x-consumer-username": "my-client" },
  "upstreamResponses": [
    {
      "statusCode": 200,
      "name": "alice",
      "zone": "zone-eu-1",
      "reason": null,
      "incomingHeaders": {},
      "upstreamResponses": []
    }
  ]
}
```

## Troubleshooting

| Symptom | Likely cause |
|---------|-------------|
| `statusCode: 403` on an upstream | The mesh MeshTrafficPermission does not allow bob → that service |
| `statusCode: 503` on an upstream | The upstream pod is down or the mesh sidecar is not injected |
| `reason: "tls handshake error"` | mTLS certificate mismatch — check the MeshTLS policy |
