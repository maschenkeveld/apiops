# APIOps — Kong Konnect GitOps Pipeline

A GitOps repository for managing Kong Konnect configuration through code. Every change to an API — from the OpenAPI spec to plugins to consumers — is version-controlled, validated, and deployed automatically via CI/CD.

The pipeline logic lives in plain shell scripts under [`scripts/`](scripts/README.md); the GitHub Actions workflows are thin wrappers that call those same scripts, so **CI and local runs are identical**.

---

## Purpose

API configuration is the source of truth. Developers define their APIs as OpenAPI specs, and the pipeline generates Kong gateway configuration, validates it, syncs it to the right Konnect control plane, and (on release) publishes it to the Developer Portal. No manual portal or Admin API interaction is required.

Key capabilities:
- Generate Kong deck configuration from OpenAPI specs
- Apply environment-specific patches (backend hostnames, routing rules) from `env-vars` files
- Attach plugins (rate limiting, OAS validation, OIDC) using shared templates
- Two blocking lint gates: OpenAPI (Spectral) and generated deck config (`deck file lint`)
- Enforce versioning discipline (semver, changelog, documented breaking changes)
- Back up Konnect state before every deployment
- Publish HTML API documentation as pipeline artifacts
- Publish APIs (spec, docs, gateway link) to the Konnect Dev Portal on release

---

## Relationship to PlatformOps

This repo is the **APIOps** half of a two-repo split. The **PlatformOps** repo (`../platformops/`) provisions the Konnect infrastructure with Terraform; APIOps deploys API configuration *into* it.

Relevant PlatformOps stacks:

- `konnect-eu-apiops-development` / `konnect-eu-apiops-production` — the gateway control planes (classic `kong/konnect` provider).
- `konnect-eu-apiops-portal` — the Developer Portal, a **standalone stack not tied to any control plane**. It provisions a **new** Konnect portal via the `kong/konnect-beta` provider (not the classic `konnect_portal`), plus a `konnect_portal_customization` for branding.

All PlatformOps stacks read/write secrets from **OpenBao** (`https://openbao.shared.pve-home.schenkeveld.io`) via the Vault-API-compatible `hashicorp/vault` provider.

The contract between the two repos is by **name and secret path**:

- PlatformOps creates control planes named `apiops-development` / `apiops-production`. APIOps uses those exact names as its `env-vars/<control-plane-name>` filenames and `control_plane_name` workflow inputs.
- The portal stack writes the portal ID to OpenBao at `kv/konnect/konnect-eu-apiops-portal/portal-details`. The APIOps release pipeline reads `portal_id` from there to publish APIs (see [Dev Portal publishing](#dev-portal-publishing)).

---

## Folder Structure

```
.
├── .github/
│   ├── workflows/              # CI/CD pipeline definitions (thin wrappers over scripts/*.sh)
│   ├── actions/                # Composite actions (build-kong-config → scripts/build.sh)
│   └── ISSUE_TEMPLATE/         # GitHub issue templates
│
├── apis/                       # One folder per API
│   └── <api-name>/
│       ├── openapi-spec/       # OpenAPI spec (source of truth for the API contract)
│       ├── plugins/            # Plugin attachments specific to this API
│       ├── additions/          # Extra deck entities to merge (e.g. consumer group associations)
│       ├── patches/            # deck file patches applied after generation (API-specific values)
│       ├── env-vars/           # Environment variable files, one per Konnect control plane
│       ├── md-files/           # Markdown docs published to the Dev Portal
│       ├── deck-file/
│       │   ├── generated/      # Generated deck configs (git-ignored build artefacts)
│       │   └── dumped/         # Per-API deck dumps (git-ignored build artefacts)
│       ├── changelog.md        # Required: version history, last line = current version
│       └── breaking-changes.yaml  # Required when introducing breaking changes
│
├── global/                     # Shared Konnect entities not tied to a single API
│   ├── deck-file/              # Source deck files for consumers, consumer groups, plugins, redis
│   ├── patches/                # Patches applied to each global deck file before syncing
│   └── env-vars/               # Control-plane-specific environment variables
│
├── shared/
│   ├── env-vars/               # Env vars shared across all APIs (e.g. dataplane hostname)
│   ├── patches/                # deck patches applied to every API (e.g. route hosts)
│   ├── plugin-templates/       # Reusable plugin config templates referenced from API plugins
│   ├── openapi-spec/           # Shared OpenAPI components (schemas, responses, parameters)
│   ├── deck-linting/           # deck (gateway) lint ruleset — counterpart to .spectral.yaml
│   └── .spectral.yaml          # Spectral ruleset for OpenAPI linting
│
├── scripts/                    # ALL the pipeline logic as shell scripts + Docker runner (see scripts/README.md)
│   ├── <step>.sh               #   one script per pipeline step (validate, build, lint, deploy, …)
│   ├── publish-api.sh          #   Dev Portal publish core (wrapped by publish.sh)
│   ├── Dockerfile + Makefile   #   pinned tooling image + `make` entry points for local runs
│   └── old/                    #   superseded single-purpose scripts, kept for reference
└── backups/                    # deck dump artefacts (uploaded to GitHub Actions, not committed)
```

### How an API is configured

Each API under `apis/<name>/` follows the same pattern. During deployment the pipeline:

1. Bundles and lints the OpenAPI spec
2. Converts it to a Kong deck file (`openapi2kong`)
3. Merges in `additions/additions.yaml` (extra Kong entities)
4. Attaches plugins from `plugins/plugins.yaml` using templates from `shared/plugin-templates/`
5. Applies `shared/patches/deck.yaml` (e.g. sets route hostnames from env vars)
6. Applies `apis/<name>/patches/deck.yaml` (e.g. sets backend service hostname from env vars)
7. Tags the result with the API name and major version
8. Namespaces all routes under `/<api-name>/<major-version>`
9. Syncs to Konnect with `--select-tag` so only this API's entities are touched

Environment-specific values (backend hostname, dataplane hostname, etc.) come from the matching `env-vars/<control-plane-name>` file, sourced before `deck gateway sync`. The patches reference them as `${{ env "DECK_*" }}`, which deck resolves at sync time. **The env-vars file name must exactly match the Konnect control plane name.**

---

## Pipelines / Workflows

The pipeline has **three layers**. The actual work (deck/redocly/spectral/oasdiff/curl) lives only in
the bottom layer — the shell scripts under [`scripts/`](scripts/README.md):

```
1. Trigger workflows      trigger-pr / trigger-main / trigger-release
   (events: PR, push,        │  bind to GitHub events; contain NO tool logic and
    release branches)        │  do NOT reference scripts/ directly — they just
                             ▼  call reusable workflows.
2. Reusable workflows     validate-apis, lint-deck, deploy-apis, …
   (GitHub glue)             │  matrix, checkout, artifacts, secrets, summaries —
                             ▼  then `run: ./scripts/<step>.sh`.
3. Scripts                scripts/*.sh   ← all the real logic, runnable locally too
```

So a trigger never mentions `scripts/`; it calls a reusable workflow, which calls the script. Example:
`trigger-main` → `uses: deploy-apis.yaml` → `run: ./scripts/deploy.sh`. Because CI and the local
runner execute the **same** scripts, they cannot drift.

```
Triggers                  Reusable workflows (→ scripts/*.sh)
──────────────────────────────────────────────────────────────
trigger-pr          ──►  validate-apis        → validate.sh
                         lint-deck            → lint.sh / lint-global.sh
                         generate-and-publish-documentation → docs.sh
trigger-main        ──►  validate-apis        → validate.sh
                         lint-deck            → lint.sh / lint-global.sh
                         backup-kong-control-plane → backup.sh
                         deploy-global-components  → deploy-global.sh
                         deploy-apis          → build.sh + deploy.sh
                         verify-deployment    → verify.sh
                         generate-and-publish-documentation → docs.sh
trigger-release     ──►  (same as trigger-main, targeting production)
                         publish-to-portal    → portal-id.sh + publish.sh   (release/prod only)
```

### Trigger Workflows

#### `trigger-pr.yaml` — Pull Request Validation
Fires on every PR opened/updated/reopened against `main`. Validation only, no deployment.

| Job | What it does |
|---|---|
| `setup-apps` | Defines which apps to validate (the `ALL_APPS` list) |
| `kong-pipeline` | `validate-apis` — OpenAPI lint + version/breaking-change checks |
| `deck-lint` | `lint-deck` — builds and lints the generated deck config (blocking) |
| `generate-docs` | `generate-and-publish-documentation` (dry run, `deploy_docs: false`) |
| `pr-summary` | Writes a summary to the step summary |

#### `trigger-main.yaml` — Development Deployment
Fires on every push to `main`. Deploys to `apiops-development`. Jobs are chained so each runs only if the previous succeeded — `validate` and `deck-lint` gate before any write to Konnect.

| Job | What it does |
|---|---|
| `setup-apps` | Defines which apps to deploy |
| `kong-pipeline` | Validate specs — gate for all downstream jobs |
| `deck-lint` | Lint the generated deck config — gate before any write |
| `kong-backup` | Back up the current control plane state |
| `kong-global` | Deploy global components (consumers, consumer groups, plugins, redis) |
| `kong-deploy` | Generate and sync all API configs to Konnect |
| `kong-verify` | Ping the control plane to confirm it is reachable |
| `documentation` | Generate HTML docs and upload as artifacts |
| `notify` | Write a deployment summary |

#### `trigger-release.yaml` — Production Deployment
Fires on push to any `release/**` or `releases/**` branch. Targets `apiops-production`. Same sequence as the dev deploy, plus a final `kong-portal` job that publishes the APIs to the Dev Portal. The branch name is parsed for the release version (e.g. `release/2.1.0` → `2.1.0`).

### Reusable Workflows

Each one runs the matching `scripts/*.sh` script (see [scripts/README.md](scripts/README.md) for the full mapping).

- **`validate-apis.yaml` → `validate.sh`** — per app: bundle + Spectral lint (`shared/.spectral.yaml`; `httpbin` exempt); then, if the bundled spec changed vs the base branch (`origin/main`, via a temporary git worktree), enforce that `changelog.md`'s last line matches the spec version, the version was incremented and is valid semver, and any `oasdiff` breaking changes are registered in `breaking-changes.yaml`.
- **`lint-deck.yaml` → `lint.sh` / `lint-global.sh`** — builds each API's deck file (via the `build-kong-config` action, the same build `deploy-apis` uses) and runs `deck file lint shared/deck-linting/ruleset.yaml … --fail-severity error`; also lints the hand-written `global/deck-file/*.yaml`. `error`-level findings fail the build; `warn`-level are reported only. Blocking gate on PRs and before every deploy. See [`shared/deck-linting/README.md`](shared/deck-linting/README.md).
- **`backup-kong-control-plane.yaml` → `backup.sh`** — `deck gateway dump` of the control plane, uploaded as an artifact (30-day retention). Validates the `environment` input first.
- **`deploy-global-components.yaml` → `deploy-global.sh`** — deploys `global-consumer-groups`, `global-consumers`, `global-plugins`, `global-redis` in sequence (`max-parallel: 1`, dependency order). Per component: patch → `deck gateway diff` → `deck gateway sync` scoped with `--select-tag <component>`. Only runs when `global/**` changed.
- **`deploy-apis.yaml` → `build.sh` + `deploy.sh`** — per app: build the deck config (via the `build-kong-config` action), then `deck gateway diff` and `sync`, scoped with `--select-tag <api> --select-tag <version>` and `--preserve-consumer-group-associations`. Env-vars are sourced so the `${{ env "DECK_*" }}` patches resolve at sync time.
- **`verify-deployment.yaml` → `verify.sh`** — `deck gateway ping` against the target control plane.
- **`generate-and-publish-documentation.yaml` → `docs.sh`** — Redocly `build-docs` → self-contained HTML per API, uploaded as `openapi-spec-html-<app>-<environment>`. The `deploy_docs` flag is reserved for future publishing and defaults to `false`.
- **`publish-to-portal.yaml` → `portal-id.sh` + `publish.sh`** — release/prod only, after deploy + verify. Reads `portal_id` from OpenBao, then per app upserts the API + uploads the bundled spec, publishes every `md-files/*.md` as a document, publishes the API to the portal, and links it to its running gateway service. Requires `KONNECT_TOKEN` and `VAULT_TOKEN`.
- **`build-kong-config` (composite action) → `build.sh`** — not a workflow; shared by `deploy-apis` and `lint-deck`. Installs the tooling, then runs `scripts/build.sh` (bundle → `openapi2kong` → additions/plugins/patches/tags/namespace). Same script locally and in CI, so the config that is linted is the config that is deployed.

---

## Running locally

Every pipeline step is a shell script in [`scripts/`](scripts/README.md), runnable inside a pinned Docker image so the toolchain is identical on any host (native on Apple Silicon). The GitHub workflows call these exact scripts, so the local runner and CI can't drift.

```bash
cp scripts/.env.example scripts/.env       # add KONNECT_TOKEN (+ PORTAL_ID for publish)
cd scripts && make image               # build the tooling image once

make validate APP=alice                # OpenAPI validate (no creds)
make build lint docs APP=alice         # offline: spec → deck → lint → HTML
make demo CP=apiops-development APPS="alice"   # full end-to-end (deploy + portal)
make dry-run APPS="alice"              # full flow, diff-only, no writes
```

Other targets: `lint-global`, `deploy`, `deploy-global`, `backup`, `verify`, `publish`. See [scripts/README.md](scripts/README.md) for the full command table and the script ↔ workflow mapping.

---

## Dev Portal publishing

The deploy path manages the Kong **gateway** (services, routes, plugins) via `deck`. The Dev Portal is a separate Konnect surface (the `/v3/apis` registry + portals), provisioned by the PlatformOps `konnect-eu-apiops-portal` stack. On release, `publish-to-portal.yaml` publishes to it.

### `scripts/publish-api.sh`

The single, parameterized publish script — used by both `scripts/publish.sh` and `publish-to-portal.yaml`. It reads config from environment variables and runs the full flow for one API (upsert API + spec → upload `md-files/` docs → publish to portal → link to the gateway service). Requires `curl`, `jq`, `yq`. Run from the repo root:

```bash
KONNECT_TOKEN=kpat_... \
PORTAL_ID=<portal-id> \
API_NAME=alice \
API_VERSION=v1 \
CONTROL_PLANE_NAME=apiops-production \
./scripts/publish-api.sh
```

> ⚠️ This script **writes to Konnect** (registry, portal, implementation). Test against a throwaway API/portal first. Defaults to the EU region (`https://eu.api.konghq.com`); override with `API_HOST`.

The earlier single-purpose scripts (`apispec.sh`, `apidocs.sh`, `apipublish.sh`, `deploy-api-to-portal.sh`, `full.sh`) are superseded by `publish-api.sh` and kept for reference in [`scripts/old/`](scripts/old/).

---

## Secrets

| Secret / input | Where used |
|---|---|
| `KONNECT_TOKEN` (secret) | All workflows that touch Konnect (backup, deploy, verify, portal) |
| `VAULT_TOKEN` (secret) | `publish-to-portal.yaml` — token for the secrets backend (OpenBao) |
| `vault_addr` / `vault_portal_path` (inputs) | `publish-to-portal.yaml` — default to the OpenBao endpoint and the `konnect-eu-apiops-portal` portal-details path; override if needed |

> The portal publish reads the portal ID from **OpenBao** (`https://openbao.shared.pve-home.schenkeveld.io`), which is Vault-API-compatible (so the `hashicorp/vault` provider and the `X-Vault-Token` header still apply). The runner must be able to reach that host. If it can't, switch `publish-to-portal.yaml` to read a `KONNECT_PORTAL_ID` GitHub variable instead.

---

## Adding a New API

1. Create `apis/<your-api>/` following an existing API (e.g. `alice`)
2. Add the OpenAPI spec at `apis/<your-api>/openapi-spec/openapi-spec.yaml`
3. Create `apis/<your-api>/env-vars/<control-plane-name>` for each target environment
4. Create `plugins/plugins.yaml`, `patches/deck.yaml`, and `additions/additions.yaml`
5. Create `changelog.md` with an initial entry: `1.0.0: "Initial version"`
6. (Optional) Add Dev Portal docs under `md-files/`
7. Add the API name to the apps list in the relevant trigger workflow(s):
   - `trigger-pr.yaml` → `ALL_APPS` (PR validation)
   - `trigger-main.yaml` → `ALL_APPS` (development deploy)
   - `trigger-release.yaml` → `PRODUCTION_APPS` (production deploy)

> Each trigger keeps its **own** apps list — a folder under `apis/` is not deployed until its name is added to the relevant list. Validate locally first with `make validate APP=<name>` and `make build lint APP=<name>`.
