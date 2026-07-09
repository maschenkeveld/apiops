# APIOps — Kong Konnect GitOps Pipeline

Manage Kong Konnect config as code. An API is defined by its OpenAPI spec; the pipeline generates
Kong gateway config from it, validates and lints it, deploys it to a Konnect control plane, and
publishes it to the API Catalog and Developer Portal.

**All pipeline logic lives in shell scripts under [`scripts/`](scripts/README.md); the GitHub
Actions workflows just call them** — so CI and local runs are identical.

## How it fits together (three layers)

```
1. Trigger workflows   trigger-pr / trigger-main / trigger-release   (bind to git events)
        │                 no tool logic — they call reusable workflows
        ▼
2. Reusable workflows  validate-apis, lint-deck, deploy-apis, …      (matrix, secrets, artifacts)
        │                 each does:  run: ./scripts/<step>.sh
        ▼
3. Scripts             scripts/*.sh                                  (the real work; run locally too)
```

Example: `trigger-main` → `uses: deploy-apis.yaml` → `run: ./scripts/deploy.sh`.

## The three flows

| Trigger | Fires on | Does |
|---|---|---|
| `trigger-pr` | PR to `main` | validate (OpenAPI lint + semver/breaking) + deck-lint. No deploy. |
| `trigger-main` | push to `main` | validate → deck-lint → backup → deploy globals → **deploy to `apiops-development`** → verify → publish to catalog + dev portal |
| `trigger-release` | push to `production` branch | same pipeline against **`apiops-production`**, then publish to catalog + dev portal |

### Promoting to production

There is no separate release branch or version tag. Promote by merging `main` into `production`:

```bash
git push origin main:production
```

The real versioning lives in each API's `changelog.md`.

## Repo layout

```
apis/<name>/     openapi-spec, plugins, additions, patches, env-vars/, md-files/, changelog.md, breaking-changes.yaml, konnect.yaml
global/          shared Konnect entities (consumers, consumer groups, plugins, redis)
shared/          plugin-templates, patches, openapi-spec components, .spectral.yaml, deck-linting/
scripts/         all pipeline logic + Docker runner (see scripts/README.md); old/ = superseded
.github/         workflows (thin wrappers) + actions/build-kong-config (→ scripts/build.sh)
```

## Add a new API

1. Create `apis/<name>/` by copying an existing one (e.g. `alice`):

   | File | Purpose |
   |---|---|
   | `openapi-spec/openapi-spec.yaml` | Source of truth for the API shape |
   | `plugins/plugins.yaml` | Kong plugins (uses templates from `shared/plugin-templates/`) |
   | `patches/deck.yaml` | Deck patches (e.g. override route hosts) |
   | `additions/additions.yaml` | Extra Kong entities not derivable from the spec |
   | `env-vars/apiops-development` | `DECK_SERVICE_BACKEND_HOSTNAME` + `DECK_SERVICE_BACKEND_PORT` for dev |
   | `env-vars/apiops-production` | Same, for production |
   | `changelog.md` | Start with `1.0.0: "Initial version"` — version must match the spec |
   | `breaking-changes.yaml` | Register any breaking changes here (enforced by `validate.sh`) |
   | `md-files/` | Optional Markdown docs published to the Dev Portal |
   | `konnect.yaml` | Controls what the publish step does (see below) |

2. Add the name to the app lists in `trigger-main.yaml` (`ALL_APPS`) and `trigger-release.yaml`
   (`PRODUCTION_APPS`). A folder isn't deployed until it's in the list.

3. Validate locally: `cd scripts && make validate build lint APP=<name>`.

> `changelog.md`'s last entry must match the spec's `info.version`; a changed spec must bump
> semver; breaking changes must be registered in `breaking-changes.yaml`. All three are enforced
> by `validate.sh` on every CI run.

## konnect.yaml

Each API has a `konnect.yaml` that controls what the publish step does. All portal/gateway names
are inferred from the flags — no IDs to manage:

```yaml
catalog: true       # publish to the Konnect API Catalog
portal: true        # publish to the Konnect Developer Portal
development: true   # include the development environment (apiops-development CP, apiops-developer-portal)
production: true    # include the production environment  (apiops-production CP,  apiops-production-portal)
```

Inferred conventions:

| Flag | Control plane | Portal | Catalog entry name |
|---|---|---|---|
| `development: true` | `apiops-development` | `apiops-developer-portal` | `{app}-dev` |
| `production: true` | `apiops-production` | `apiops-production-portal` | `{app}` |

The service name in every gateway is always the app folder name. All IDs are resolved by name at
runtime — no hardcoded UUIDs anywhere.

## Global components

`global/` holds shared Konnect entities that apply across all APIs: consumer groups, consumers,
Redis config, and global plugins. These are deployed via `deploy-global-components.yaml`, called
before the per-API deploy in both flows. On production, `force_deploy: true` ensures they always
sync — even if no `global/` files changed — to bootstrap a fresh control plane cleanly.

## Run locally

Everything runs in a pinned Docker image (native on Apple Silicon), using the same scripts as CI:

```bash
cd scripts && cp .env.example .env   # add KONNECT_TOKEN
make image                           # build the tooling image once

make validate build lint APP=alice   # offline — no Konnect needed
make deploy APP=alice                # diff + sync alice to apiops-development
make demo APPS="alice bob"           # full end-to-end (validate → deploy → verify → publish)
make dry-run APPS="alice bob"        # same but diff-only, no writes
```

See [scripts/README.md](scripts/README.md) for the full command reference.

## CI configuration

Only one secret is required:

| Name | Type | Purpose |
|---|---|---|
| `KONNECT_TOKEN` | Secret | Konnect PAT — used by every workflow that talks to Konnect |

Portal and gateway IDs are resolved by name at runtime, so no portal ID variable is needed.

By default the pipeline talks only to the public Konnect API, so it runs on free GitHub-hosted
runners — no secrets backend, no self-hosted runner required.

## Relationship to PlatformOps

[PlatformOps](../platformops/) provisions the infrastructure with Terraform: the
`konnect-eu-apiops-{development,production}` stacks each create a control plane and a portal.
APIOps deploys config into what PlatformOps created. The contract between them is by **name** —
control planes `apiops-development` / `apiops-production` match the `env-vars/<name>` files, and
portal names `apiops-developer-portal` / `apiops-production-portal` are resolved by `publish-api.sh`
at runtime.
