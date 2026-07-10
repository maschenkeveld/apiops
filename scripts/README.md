# scripts/ — pipeline logic & local runner

This folder holds **all the pipeline logic** as one shell script per step plus a Docker
`Makefile`/`Dockerfile` runner and `old/` for superseded scripts. Run the whole pipeline locally —
same steps as CI, no GitHub Actions — inside a pinned Docker image so the toolchain is identical
on any host (including Apple Silicon, natively).

These scripts are the **single source of truth**: every GitHub Actions workflow calls them directly
(`run: ./scripts/<step>.sh`). So the local runner and CI can never drift — the workflows are just
thin GitHub glue (matrix, checkout, artifacts, secrets, summaries) around `scripts/*.sh`.

## Prerequisites

- Docker.
- For deploy/verify/publish: a Konnect PAT. Copy [.env.example](.env.example) to `scripts/.env`
  and fill it in (gitignored).

```bash
cp scripts/.env.example scripts/.env   # then add KONNECT_TOKEN
make image                             # build the tooling image once
```

## Commands (run from this `scripts/` dir)

| Command | What it does | Needs creds? |
|---|---|---|
| `make demo APPS="alice bob"` | Full flow: validate → generate → lint → deploy → verify → publish | yes |
| `make dry-run APPS="alice bob"` | Same but `deck gateway diff` only, no writes | yes (read-only) |
| `make validate APP=alice` | OpenAPI validate (spectral + changelog/semver/breaking vs main) | no |
| `make generate APP=alice` | Generate the deck config for one API | no |
| `make lint APP=alice` | `deck file lint` the generated config | no |
| `make lint-global` | `deck file lint` the global deck files | no |
| `make deploy APP=alice` | diff + sync one API to `CP` (`DRY_RUN=1` for diff only) | yes |
| `make deploy-global` | diff + sync global components to `CP` (`DRY_RUN=1` for diff only) | yes |
| `make backup` | dump `CP` state to `backups/` | yes |
| `make verify` | ping the control plane | yes |
| `make shell` | shell inside the tooling image | no |

Variables: `CP` (control plane, default `apiops-development`), `APP` (single app), `APPS`
(space-separated list for `demo`/`dry-run`), `IMAGE`/`TAG`.

```bash
# Offline — no Konnect, no creds: prove spec → deck → lint
make generate lint APP=alice

# Full end-to-end demo against development
make demo CP=apiops-development APPS="alice bob"
```

## How it maps to the pipeline

Every pipeline step is a script here; the matching workflow is a thin wrapper that calls it.

| Script | Called by |
|---|---|
| `validate.sh` | `validate-apis.yaml` |
| `generate.sh` | `generate-kong-config` action (used by `generate-deck.yaml`) |
| `lint.sh` | `lint-deck.yaml` (per-API) |
| `lint-global.sh` | `lint-deck.yaml` (global files) |
| `backup.sh` | `deploy-apis.yaml` (before each app) + `deploy-global-components.yaml` (before global sync) |
| `deploy-global.sh` | `deploy-global-components.yaml` |
| `deploy.sh` | `deploy-apis.yaml` |
| `verify.sh` | `verify-deployment.yaml` |
| `publish-api.sh` | `publish-to-catalog.yaml` (`PUBLISH_MODE=catalog`) and `publish-to-portal.yaml` (`PUBLISH_MODE=portal`) |
| `lib.sh` | sourced by all other scripts (shared helpers, env-var loading) |
| `demo.sh` | local orchestration — chains per-app steps like the trigger workflows |
| `control-plane.sh` | env → control-plane name mapping |

In CI the deck is **generated once** (`generate-deck.yaml` → `deck-<app>` artifact); `lint-deck.yaml`
and `deploy-apis.yaml` download that artifact instead of regenerating. `deploy.sh` and `lint.sh`
therefore expect the generated file to already exist (locally, `make generate` produces it first).

## Notes

- `generate`/`lint`/`validate` never touch Konnect (env-vars resolve at sync time, matching CI).
- `deploy`/`publish-api.sh` write to live Konnect — for offline checks use `make dry-run` or
  `make generate lint`.
- The image installs the real `deck` and `kongctl` releases per-arch.
