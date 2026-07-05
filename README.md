# APIOps — Kong Konnect GitOps Pipeline

Manage Kong Konnect config as code. An API is defined by its OpenAPI spec; the pipeline generates
Kong gateway config from it, validates and lints it, deploys it to a Konnect control plane, and (on
release) publishes it to the Developer Portal.

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

## The flow

| Trigger | Fires on | Does |
|---|---|---|
| `trigger-pr` | PR to `main` | validate (OpenAPI lint + semver/breaking) → deck-lint → docs (dry run). No deploy. |
| `trigger-main` | push to `main` | validate → deck-lint → backup → deploy globals → deploy APIs → verify → docs, to `apiops-development` |
| `trigger-release` | push to `release/**` | same as main against `apiops-production`, then **publish to the Dev Portal** |

Each step maps to one script: `validate.sh`, `build.sh`, `lint.sh`/`lint-global.sh`, `backup.sh`,
`deploy-global.sh`, `deploy.sh`, `verify.sh`, `docs.sh`, `publish.sh`. See
[scripts/README.md](scripts/README.md) for the full mapping.

## Repo layout

```
apis/<name>/     openapi-spec, plugins, additions, patches, env-vars/<cp>, md-files, changelog.md, breaking-changes.yaml
global/          shared Konnect entities (consumers, consumer groups, plugins, redis)
shared/          plugin-templates, patches, openapi-spec components, .spectral.yaml, deck-linting/ruleset.yaml
scripts/         all pipeline logic + Docker runner (see scripts/README.md); old/ = superseded scripts
.github/         workflows (thin wrappers) + actions/build-kong-config (→ scripts/build.sh)
```

## Add a new API
1. Create `apis/<name>/` like an existing one (e.g. `alice`): `openapi-spec/openapi-spec.yaml`,
   `plugins/plugins.yaml`, `patches/deck.yaml`, `additions/additions.yaml`,
   `env-vars/<control-plane-name>`, `changelog.md` (`1.0.0: "Initial version"`), optional `md-files/`.
2. Add the name to the app list in the relevant trigger(s): `ALL_APPS` (pr/main), `PRODUCTION_APPS` (release).
3. Validate locally: `cd scripts && make validate build lint APP=<name>`.

> `changelog.md`'s last line must match the spec version; a changed spec must bump semver; breaking
> changes must be registered in `breaking-changes.yaml`. These are enforced by `validate.sh`.

## Run locally

Everything runs in a pinned Docker image (native on Apple Silicon), using the same scripts as CI:

```bash
cd scripts && cp .env.example .env   # add KONNECT_TOKEN (+ PORTAL_ID for publish)
make image
make validate build lint APP=alice           # offline, no creds
make demo CP=apiops-development APPS="alice"  # full end-to-end
make dry-run APPS="alice"                     # diff only, no writes
```

## CI configuration (GitHub → Settings → Secrets and variables → Actions)

| Name | Type | Needed |
|---|---|---|
| `KONNECT_TOKEN` | secret | always |
| `KONNECT_PORTAL_ID` | variable | release publish (production portal id; `terraform output portal_id`) |
| `PORTAL_READ_FROM_OPENBAO` | variable | optional — `"true"` to read the portal id from OpenBao instead |
| `VAULT_TOKEN` | secret | only when `PORTAL_READ_FROM_OPENBAO=true` |

By default the pipeline talks **only to the public Konnect API**, so it runs on free GitHub-hosted
runners — no secrets backend, no self-hosted runner.

## Relationship to PlatformOps

[PlatformOps](../platformops/) provisions the infra with Terraform: the
`konnect-eu-apiops-{development,production}` stacks each create a control plane **and** a portal
(dev + prod). APIOps deploys config into it. The contract is by **name** (control planes
`apiops-development` / `apiops-production`, matching the `env-vars/<name>` files) and the **portal
id** (from `terraform output portal_id` → the `KONNECT_PORTAL_ID` variable). Dev Portal publishing is
release/prod only; where it reads the portal id is the `read_from_openbao` toggle above.
