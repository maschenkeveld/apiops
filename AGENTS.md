# AGENTS.md

Operational guide for agents. Read [README.md](README.md) for the overview.

## What this repo is
GitOps for **Kong Konnect** — no app to build. Deliverables: OpenAPI specs + deck config under
`apis/`, `global/`, `shared/`; **all pipeline logic in `scripts/*.sh`**; and `.github/` workflows that
are thin wrappers calling those scripts (`run: ./scripts/<step>.sh`). Edit pipeline logic in
`scripts/`, never inline in YAML, or CI and the local runner drift.

Two Konnect surfaces: **gateway** (deck sync, every deploy) vs **Dev Portal** (publish on release
only). Don't conflate them.

Paired with **PlatformOps** (`../platformops/`): each `konnect-eu-apiops-{development,production}`
stack provisions a control plane + a portal. Contract = **name** (`apiops-development` /
`apiops-production`, matching `env-vars/<name>` files) + **portal id** (`terraform output portal_id`
→ `KONNECT_PORTAL_ID` variable).

## Tooling & gates
`deck` (generate/lint/sync), `redocly` (bundle/docs), `spectral` (OAS lint), `oasdiff` (breaking
changes), `yq`+`jq`. Two **blocking** lint gates: OpenAPI (Spectral, `shared/.spectral.yaml`) and
deck (`deck file lint`, `shared/deck-linting/ruleset.yaml`).

## Local checks (no creds for the offline subset)
```bash
cd scripts && make image
make validate build lint APP=<api>   # OAS lint + build + deck lint, no Konnect
make dry-run APPS="<api>"            # full flow, diff only (read-only)
```
Prefer `make dry-run` / `deck gateway diff` — never `sync` — when inspecting locally.

## Hard rules
- **Never run `deck gateway sync`, `scripts/publish.sh`/`publish-api.sh`, `deploy*.sh`**, or anything that writes to Konnect/OpenBao unless explicitly asked. `diff`, `dump`, `ping`, `lint`, `validate`, `build`, `docs` are safe.
- **Never commit** tokens (keep `TOKEN=`/env placeholders blank) or build artifacts (`deck-file/generated/`, `deck-file/dumped/`, `openapi-spec-bundled*`, `backups/*.yaml` are git-ignored).
- Secrets/vars: `KONNECT_TOKEN` (secret), `KONNECT_PORTAL_ID` (var); `VAULT_TOKEN` only if `PORTAL_READ_FROM_OPENBAO=true`.

## Enforced conventions (validate.sh, on spec change vs `main`)
- `changelog.md` last line `<version>: "..."` matches the spec's `info.version`.
- Version is valid semver and incremented.
- Breaking changes (oasdiff) must have a matching entry in `breaking-changes.yaml`.

## Where things live
- Spec → `apis/<name>/openapi-spec/openapi-spec.yaml`; plugins → `plugins/plugins.yaml` (templates in `shared/plugin-templates/`); patches → `patches/deck.yaml` (+ `shared/patches/deck.yaml`); extra entities → `additions/additions.yaml`; portal docs → `md-files/`.
- Env values → `env-vars/<control-plane-name>` and `shared/env-vars/<control-plane-name>`. **Filename must equal the Konnect control-plane name**; sourced before deck (patches use `${{ env "DECK_*" }}`, resolved at sync).
- Global entities (consumers, consumer groups, plugins, redis) → `global/`.

## Editing workflows
- `trigger-*.yaml` = entry points (events); `<verb>-*.yaml` = reusable workflows they call.
- Script mapping: `validate-apis`→`validate.sh`, build action→`build.sh`, `lint-deck`→`lint.sh`+`lint-global.sh`, `docs`→`docs.sh`, `backup`→`backup.sh`, `deploy-global`→`deploy-global.sh`, `deploy-apis`→`deploy.sh`, `verify`→`verify.sh`, `publish-to-portal`→`publish.sh` (+ `portal-id.sh` when `read_from_openbao=true`).
- Deploy jobs are chained on `success` with `deck-lint` gating before any write; gateway writes are `--select-tag <api> <version>` scoped. Preserve both.
- Apps lists are hard-coded per trigger (`ALL_APPS` in pr/main, `PRODUCTION_APPS` in release) and can drift from `apis/` folders — a folder isn't deployed until it's in the list.
- Scripts log to stderr, print data (paths/ids) to stdout, so workflows can capture output.

## Style
Match surrounding files: workflows are heavily commented on *why* a step exists; bash scripts source `lib.sh` and use uppercase config vars.
