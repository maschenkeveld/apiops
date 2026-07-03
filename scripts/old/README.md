# Legacy scripts (superseded)

These are the original, hardcoded, single-purpose Dev Portal scripts. They have been **consolidated
into [`../publish-api.sh`](../publish-api.sh)** (env-driven, used by CI and the local runner).

Nothing in the pipeline references them — kept only for reference.

| Script | Original purpose |
|---|---|
| `apispec.sh` | Create/update an API + upload its OpenAPI spec |
| `apidocs.sh` | Upload one markdown file as an API document |
| `apipublish.sh` | Publish an existing API to a Dev Portal |
| `deploy-api-to-portal.sh` | Full flow (spec + docs + publish + gateway link) |
| `full.sh` | Same flow, with token/org pre-filled for local use |

Prefer `publish-api.sh`. Do not commit real tokens into any of these.
