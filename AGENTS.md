# AGENTS.md

Operational guide for AI agents working in this repository. For the full conceptual overview, read [README.md](README.md) first.

## What this repo is

A GitOps repo for **Kong Konnect**. There is no application to build or run — the deliverables are:

- **OpenAPI specs + deck config** under `apis/`, `global/`, `shared/` — deployed to the Kong **gateway** via `deck` from GitHub Actions.
- **GitHub Actions workflows** under `.github/workflows/` (+ the `build-kong-config` composite action in `.github/actions/`) — the pipeline itself.
- **Bash scripts** under `scripts/` — Dev Portal publishing. `scripts/publish-api.sh` is the current parameterized (env-driven) entry point, called by `publish-to-portal.yaml` and runnable locally; the other scripts are legacy hardcoded versions.
- **`scripts/`** — **all pipeline logic** as one shell script per step, plus `publish-api.sh`, a Docker `Makefile`/`Dockerfile` runner (`make demo`), and `old/` (superseded scripts). These scripts are the **single source of truth**: every reusable workflow calls them (see the mapping under *Editing workflows*). Edit pipeline logic **here**, never inline in the YAML, to avoid drift.

Two distinct Konnect surfaces: **gateway** (deck sync, automated on every deploy) vs **API registry / Dev Portal** (publish on release only). Don't conflate them.

This is the APIOps half of a two-repo split with **PlatformOps** (`../platformops/`), which provisions the control planes and the Dev Portal via Terraform. The contract is by **name** (control planes `apiops-development` / `apiops-production`, from the `konnect-eu-apiops-{development,production}` stacks) and **OpenBao path** (the standalone `konnect-eu-apiops-portal` stack writes the portal ID to `kv/konnect/konnect-eu-apiops-portal/portal-details`, which the release pipeline reads). The portal stack is intentionally decoupled from any control plane and uses the **`kong/konnect-beta`** provider (the "new" Konnect portals, not the classic `konnect_portal`). All PlatformOps stacks talk to **OpenBao** (`openbao.shared.pve-home.schenkeveld.io`) via the Vault-API-compatible `hashicorp/vault` provider.

## Tooling

Changes are validated with these CLIs (assume they may not be installed locally — check first):

- `deck` (Kong decK) — generate, lint (`deck file lint`) and sync gateway config
- `redocly` (`@redocly/cli`) — bundle/lint OpenAPI specs, build HTML docs
- `spectral` (`@stoplight/spectral-cli`) — lint specs against `shared/.spectral.yaml`
- `oasdiff` — detect breaking API changes
- `yq` + `jq` — YAML/JSON manipulation (used by deck pipeline and scripts)

Two blocking lint gates run in CI: **OpenAPI** (Spectral, `shared/.spectral.yaml`, in `validate-apis.yaml`) and **deck** (`deck file lint`, `shared/deck-linting/ruleset.yaml`, in `lint-deck.yaml`). `deck file lint` is Spectral-based but its rule paths target the deck state file (`$.services`, `$.plugins`, …).

## Local checks before proposing a change

There is no test suite. The easiest faithful check is the **local runner** (same scripts CI calls),
which needs no creds for the offline subset:

```bash
cd scripts && make image        # once
make build lint APP=<api>        # bundle → deck → deck file lint, no Konnect
make validate APP=<api>          # Spectral OpenAPI lint
make dry-run APPS="<api>"        # full flow but deck gateway diff only (read-only)
```

Or run the underlying tools directly:

```bash
redocly bundle apis/<api>/openapi-spec/openapi-spec.yaml -o /tmp/bundled.yaml
spectral lint /tmp/bundled.yaml --ruleset shared/.spectral.yaml --verbose
oasdiff breaking <main-bundled.yaml> /tmp/bundled.yaml
./scripts/build.sh <api> && ./scripts/lint.sh <api>     # build then deck-lint
```

Prefer `deck gateway diff` / `make dry-run` (never `sync`) when inspecting config locally — `sync` writes to a live control plane.

## Hard rules

- **Never run `deck gateway sync`, `scripts/publish-api.sh`, or any script that PATCHes/POSTs to Konnect** unless the user explicitly asks. These mutate live control planes / portals. `diff`, `dump`, `ping`, and `lint` are safe.
- **Never commit a token.** Scripts use env vars / blank `TOKEN=` placeholders; keep them blank. The pipeline uses the `KONNECT_TOKEN` and `VAULT_TOKEN` GitHub secrets. The PlatformOps prod stack reads `KPAT`/`HCV_ROOT_TOKEN` from `TF_VAR_*` — never hardcode them in `*.tf` (this was previously a bug).
- **Never commit build artifacts.** `deck-file/generated/`, `deck-file/dumped/`, `openapi-spec-bundled*`, and `backups/*.yaml` are git-ignored — leave them that way.

## Conventions that the pipeline enforces

When a spec under `apis/<name>/` changes, `validate-apis.yaml` requires all of:

- **`changelog.md`** exists; its **last line** is `<version>: "<description>"`, and `<version>` matches the OpenAPI spec's `info.version`.
- The version is a **valid semver** and is **incremented** relative to `main`.
- If `oasdiff` finds **breaking changes**, the new version must have an entry in **`breaking-changes.yaml`**.

Keep these in sync in the same change — bumping the spec version without updating `changelog.md` fails the PR.

## Where things live (when editing)

- API contract → `apis/<name>/openapi-spec/openapi-spec.yaml`
- Per-API plugins → `apis/<name>/plugins/plugins.yaml` (templates in `shared/plugin-templates/`)
- Per-API deck patches → `apis/<name>/patches/deck.yaml`; repo-wide patches → `shared/patches/deck.yaml`
- Extra deck entities → `apis/<name>/additions/additions.yaml`
- Env-specific values → `apis/<name>/env-vars/<control-plane-name>` and `shared/env-vars/<control-plane-name>`
  - **The file name must exactly match the Konnect control plane name.** It is sourced as a shell file before deck runs.
- Global entities (consumers, consumer groups, plugins, redis) → `global/`
- Dev Portal markdown docs → `apis/<name>/md-files/`

## Apps lists (common drift point)

Each trigger workflow holds its **own** hard-coded apps list, and these can drift from the folders under `apis/`:

- `trigger-pr.yaml` → `ALL_APPS`
- `trigger-main.yaml` → `ALL_APPS`
- `trigger-release.yaml` → `PRODUCTION_APPS`

When adding or renaming an API, update the relevant list(s). If asked to "deploy" an API, confirm it is present in the right list — a folder existing under `apis/` is not enough.

## Editing workflows

- `trigger-*.yaml` = when/what runs (entry points). `<verb>-*.yaml` = reusable workflows called via `uses:`.
- Deploy jobs are chained with `if: needs.<prev>.result == 'success'` so the backup always runs before any write. `deck-lint` (from `lint-deck.yaml`) is a blocking gate before any deploy. Preserve this gating when editing.
- Gateway writes are scoped with `--select-tag <api-name> --select-tag <version>` so APIs don't clobber each other. Keep tag scoping on any new `deck gateway diff`/`sync` step.
- **Every pipeline step's logic lives in `scripts/*.sh`** — the workflows are thin wrappers that call them (matrix/checkout/artifacts/secrets/summaries stay in YAML; tool logic does not). Mapping: `validate-apis`→`validate.sh`, `build-kong-config` action→`build.sh`, `lint-deck`→`lint.sh`+`lint-global.sh`, `generate-and-publish-documentation`→`docs.sh`, `backup-kong-control-plane`→`backup.sh`, `deploy-global-components`→`deploy-global.sh`, `deploy-apis`→`deploy.sh`, `verify-deployment`→`verify.sh`, `publish-to-portal`→`portal-id.sh`+`publish.sh`. **Edit pipeline logic in `scripts/`, never inline in the YAML** — otherwise CI and the local runner drift. Scripts log to stderr and print data (paths/IDs) to stdout so workflows can capture them.
- `publish-to-portal.yaml` runs **release/prod only**. It reads the portal ID from **OpenBao** (`https://openbao.shared.pve-home.schenkeveld.io`, Vault-API-compatible — `VAULT_TOKEN` secret, `X-Vault-Token` header); if the runner can't reach it, the documented fallback is a `KONNECT_PORTAL_ID` GitHub variable.

## Style

Match the surrounding files: YAML workflows are heavily commented explaining *why* a step exists — keep that. Bash scripts use uppercase variables at the top of the file for configuration.
