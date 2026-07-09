# AGENTS.md

Operational guide for agents. Read [README.md](README.md) for the overview.

## What this repo is

GitOps for **Kong Konnect** — no app to build. Deliverables: OpenAPI specs + deck config under
`apis/`, `global/`, `shared/`; **all pipeline logic in `scripts/*.sh`**; and `.github/` workflows
that are thin wrappers calling those scripts (`run: ./scripts/<step>.sh`). Edit pipeline logic in
`scripts/`, never inline in YAML, or CI and the local runner drift.

Two Konnect surfaces: **gateway** (deck sync, every deploy) vs **API Catalog + Dev Portal**
(published after every successful deploy on both main and production). Don't conflate them.

Paired with **PlatformOps** (`../platformops/`): each `konnect-eu-apiops-{development,production}`
stack provisions a control plane + a portal. Contract = **name** (`apiops-development` /
`apiops-production`, matching `env-vars/<name>` files; `apiops-developer-portal` /
`apiops-production-portal` for the portals). No hardcoded UUIDs — everything is resolved by name
at runtime.

## Tooling & gates

`deck` (generate/lint/sync), `redocly` (bundle), `spectral` (OAS lint), `oasdiff` (breaking
changes), `kongctl` (catalog/portal sync), `yq`+`jq`. Two **blocking** lint gates: OpenAPI
(Spectral, `shared/.spectral.yaml`) and deck (`deck file lint`, `shared/deck-linting/ruleset.yaml`).

## Local checks (no creds for the offline subset)

```bash
cd scripts && make image
make validate build lint APP=<api>   # OAS lint + build + deck lint, no Konnect
make dry-run APPS="<api>"            # full flow, diff only (read-only)
```

Prefer `make dry-run` / `deck gateway diff` — never `sync` — when inspecting locally.

## Hard rules

- **Never run `deck gateway sync`, `scripts/deploy*.sh`, `scripts/publish-api.sh`**, or anything
  that writes to Konnect unless explicitly asked. `diff`, `dump`, `ping`, `lint`, `validate`,
  `build` are safe.
- **Never commit** tokens (keep `TOKEN=`/env placeholders blank) or build artifacts
  (`deck-file/generated/`, `deck-file/dumped/`, `openapi-spec-bundled*`, `backups/*.yaml` are
  git-ignored).
- Only one CI secret: `KONNECT_TOKEN`. No portal IDs or vault tokens needed.

## Enforced conventions (`validate.sh`, on spec change vs `main`)

- `changelog.md` last line `<version>: "..."` matches the spec's `info.version`.
- Version is valid semver and incremented.
- Breaking changes (oasdiff) must have a matching entry in `breaking-changes.yaml`.

## Where things live

- Spec → `apis/<name>/openapi-spec/openapi-spec.yaml`; plugins → `plugins/plugins.yaml` (templates
  in `shared/plugin-templates/`); patches → `patches/deck.yaml` (+ `shared/patches/deck.yaml`);
  extra entities → `additions/additions.yaml`; portal docs → `md-files/`.
- Env values → `env-vars/<control-plane-name>` and `shared/env-vars/<control-plane-name>`.
  **Filename must equal the Konnect control-plane name**; sourced before deck (patches use
  `${{ env "DECK_*" }}`, resolved at sync).
- Global entities (consumers, consumer groups, plugins, redis) → `global/`.
- Publish config → `apis/<name>/konnect.yaml`: four boolean flags (`catalog`, `portal`,
  `development`, `production`). All CP/portal names and catalog entry names are inferred —
  see README for the convention table.

## Editing workflows

- `trigger-*.yaml` = entry points (events); `<verb>-*.yaml` = reusable workflows they call.
- Production is the `production` git branch. Promote with `git push origin main:production`.
- Script mapping:

  | Script | Called by |
  |---|---|
  | `validate.sh` | `validate-apis.yaml` |
  | `build.sh` | `build-kong-config` action (used by `deploy-apis.yaml` + `lint-deck.yaml`) |
  | `lint.sh` | `lint-deck.yaml` (per-API) |
  | `lint-global.sh` | `lint-deck.yaml` (global files) |
  | `backup.sh` | `backup-kong-control-plane.yaml` |
  | `deploy-global.sh` | `deploy-global-components.yaml` |
  | `deploy.sh` | `deploy-apis.yaml` |
  | `verify.sh` | `verify-deployment.yaml` |
  | `publish-api.sh` | `publish-to-catalog.yaml` (both PUBLISH_MODE=catalog and portal) |

- App lists are hard-coded per trigger (`ALL_APPS` in main, `PRODUCTION_APPS` in release) and can
  drift from `apis/` folders — a folder isn't deployed until it's in the list.
- Deploy jobs are chained on `success` with `deck-lint` gating before any write; gateway writes
  are `--select-tag <api> <version>` scoped. Preserve both.
- `force_deploy: true` on `deploy-global-components.yaml` in the production trigger ensures global
  components always sync, even with no `global/` file changes (bootstraps a fresh control plane).
- Scripts log to stderr, print data (paths/ids) to stdout, so workflows can capture output.

## Style

Match surrounding files: workflows are heavily commented on *why* a step exists; bash scripts
source `lib.sh` and use uppercase config vars.
