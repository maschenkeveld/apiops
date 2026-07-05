# Getting Started with Alice

Alice is a demo microservice that exposes identity, health, crawl, and metrics endpoints. It runs inside the Kong Mesh service mesh and is fronted by a Kong Gateway data plane.

## Base URL

```
https://kong-proxy-dp-konnect-eu-apiops-development.schenkeveld.io/alice/v1
```

## Authentication

All endpoints require a valid JWT issued by the Kong OIDC provider. Include it as a Bearer token:

```http
Authorization: Bearer <your-token>
```

To obtain a token using client credentials:

```bash
curl -s -X POST https://keycloak.schenkeveld.io/realms/kong/protocol/openid-connect/token \
  -d grant_type=client_credentials \
  -d client_id=<client_id> \
  -d client_secret=<client_secret> \
  | jq -r .access_token
```

## Quick Test

```bash
TOKEN=$(curl -s -X POST https://keycloak.schenkeveld.io/realms/kong/protocol/openid-connect/token \
  -d grant_type=client_credentials \
  -d client_id=<client_id> \
  -d client_secret=<client_secret> \
  | jq -r .access_token)

curl -H "Authorization: Bearer $TOKEN" \
  https://kong-proxy-dp-konnect-eu-apiops-development.schenkeveld.io/alice/v1/identify
```

## Endpoints Overview

| Method | Path       | Description                          |
|--------|------------|--------------------------------------|
| GET    | /health    | Liveness and readiness probe         |
| GET    | /identify  | Returns service identity and headers |
| GET    | /metrics   | Prometheus-compatible metrics        |
| POST   | /crawl     | Recursively crawls upstream services |
