# scripts/ — pipeline logic & local runner

This folder holds **all the pipeline logic** as one shell script per step (plus `publish-api.sh`,
the Docker `Makefile`/`Dockerfile` runner, and `old/` for superseded scripts). Run the whole
pipeline locally — same steps as CI, no GitHub Actions — inside a pinned Docker image so the
toolchain is identical on any host (including Apple Silicon, natively).

This is **not a fork** of the pipeline logic: these scripts are the single source of truth for
**every** pipeline step, and the GitHub Actions workflows call these same scripts (a reusable
workflow does `run: ./scripts/<step>.sh`). So the demo and CI can't drift — the workflows are just
thin GitHub glue (matrix, checkout, artifacts, secrets, summaries) around `scripts/*.sh`.

## Prerequisites

- Docker.
- For deploy/verify/publish: a Konnect PAT (and a Dev Portal ID for publish). Copy
  [.env.example](.env.example) to `scripts/.env` and fill it in (gitignored).

```bash
cp scripts/.env.example scripts/.env   # then edit
make image                          # build the tooling image once
```

## Commands (run from this `scripts/` dir)

| Command | What it does | Needs creds? |
|---|---|---|
| `make demo` | Full flow for `APPS`: validate → build → lint → docs → deploy → verify → publish | yes (+ PORTAL_ID) |
| `make dry-run` | Same but `deck gateway diff` only, no writes, no publish | yes (read-only) |
| `make validate APP=alice` | OpenAPI validate (spectral + changelog/semver/breaking vs main) | no |
| `make build APP=alice` | Build the deck config for one API | no |
| `make lint APP=alice` | `deck file lint` the built config | no |
| `make lint-global` | `deck file lint` the global deck files | no |
| `make docs APP=alice` | Build self-contained HTML docs | no |
| `make deploy APP=alice` | diff + sync one API to `CP` (`DRY_RUN=1` for diff only) | yes |
| `make deploy-global` | diff + sync global components to `CP` (`DRY_RUN=1` for diff only) | yes |
| `make backup` | dump `CP` state to `backups/` | yes |
| `make verify` | ping the control plane | yes |
| `make publish APP=alice` | publish one API to the Dev Portal | yes (+ PORTAL_ID) |
| `make shell` | shell inside the tooling image | no |

Variables: `CP` (control plane, default `apiops-development`), `APP` (single app), `APPS`
(space-separated list for `demo`/`dry-run`), `IMAGE`/`TAG`.

```bash
# Offline — no Konnect, no creds: prove spec → deck → lint
make build lint APP=alice

# Full end-to-end demo against development
make demo CP=apiops-development APPS="alice"
```

## How it maps to the pipeline

Every pipeline step is a script here; the matching workflow is a thin wrapper that calls it.
`demo.sh` chains the per-app steps like the trigger workflows do.

| Script | Workflow that calls it |
|---|---|
| `validate.sh` | `validate-apis.yaml` |
| `build.sh` | `build-kong-config` action (used by `deploy-apis.yaml` + `lint-deck.yaml`) |
| `lint.sh` | `lint-deck.yaml` (per-API) |
| `lint-global.sh` | `lint-deck.yaml` (global files) |
| `docs.sh` | `generate-and-publish-documentation.yaml` |
| `backup.sh` | `backup-kong-control-plane.yaml` |
| `deploy-global.sh` | `deploy-global-components.yaml` |
| `deploy.sh` | `deploy-apis.yaml` |
| `verify.sh` | `verify-deployment.yaml` |
| `portal-id.sh` + `publish.sh` | `publish-to-portal.yaml` (publish.sh wraps `scripts/publish-api.sh`) |
| `control-plane.sh` | env→control-plane mapping used by several workflows |
| `demo.sh` | the `trigger-*` orchestration |

`lib.sh` holds shared helpers (`log`/`die`, `cp_for_env`) and sources the same
`env-vars/<control-plane>` files the workflows use — so backend hostnames, ports and the dataplane
host come from one place.

## Notes

- `build`/`lint` never touch Konnect (env-vars resolve at sync time, matching CI).
- `deploy`/`publish` write to live Konnect/the portal — for offline demos use `make dry-run`
  or `make build lint`.
- The image installs the real `deck` release per-arch, so it does not use the repo's
  `custom-deck-linux-amd64` (amd64-only) binary.
