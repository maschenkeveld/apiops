# deck linting

Linting rules for the generated Kong **deck** (gateway) configuration. This is the deck-level
counterpart to the OpenAPI linting done with Spectral in `validate-apis.yaml`.

`deck file lint` is built on [Spectral](https://stoplight.io/open-source/spectral), so
[`ruleset.yaml`](ruleset.yaml) is a Spectral ruleset — but its `given` JSONPaths target the
decK state file (`$.services`, `$.services[*].routes`, `$.plugins`, …) rather than an OpenAPI
document.

## Rules

| Rule | Severity | What it enforces |
|---|---|---|
| `service-must-have-name` / `-tags`, `route-must-have-name` / `-tags`, `plugin-must-have-name` | error | Naming and tagging (tags make `--select-tag` syncs safe) |
| `route-should-strip-path` | warn | Explicit `strip_path` |
| **`allowed-plugins`** | **error** | **Only approved plugins may be deployed, at any level. Anything else fails the pipeline.** |
| `pre-function-only-namespace-strip`, `pre-function-access-phase-only` | error | `pre-function` (arbitrary Lua) only with the code `deck file namespace` generates |
| `cors-no-wildcard-origin` | warn | No `*` CORS origin |

### Approved plugins

`openid-connect`, `key-auth`, `acl`, `rate-limiting-advanced`, `cors`, `correlation-id`,
`request-transformer`, `response-transformer`, `oas-validation`, `prometheus`, and `pre-function`
(namespace strip only). This is an example list to show the mechanism; adjust it to your policy.

### Adding a plugin

1. Add its name to the `match` regex of `allowed-plugins` in [`ruleset.yaml`](ruleset.yaml).
2. Add it to [`tests/good.yaml`](tests/good.yaml).
3. Run `make lint-test` (from `scripts/`) — good must pass, every `tests/bad-*.yaml` must be rejected.
4. Get the change reviewed like any other policy change.

### Testing the rules

`scripts/lint-test.sh` (`make lint-test`) lints the fixtures in [`tests/`](tests/). It fails if `good.yaml` is
rejected, if a `bad-*.yaml` is accepted, or if deck crashes. Needs **deck 1.57.0 or newer**; older versions
do not enforce every rule (see `AGENTS.md`).

## Running locally

```bash
# Build a deck file the same way the pipeline does, then lint it:
redocly bundle apis/<api>/openapi-spec/openapi-spec.yaml -o /tmp/bundled.yaml
deck file openapi2kong -s /tmp/bundled.yaml > /tmp/generated.yaml
# ...(apply additions/plugins/patches/namespace as in deploy-apis.yaml)...

deck file lint shared/deck-linting/ruleset.yaml /tmp/generated.yaml --fail-severity error
```

## In CI

`lint-deck.yaml` builds each API's deck file (and reads the hand-written `global/deck-file/*.yaml`)
and runs `deck file lint … --fail-severity error`. `error`-level findings fail the build; `warn`
findings are reported but do not block. It runs as a blocking gate on PRs (`trigger-pr.yaml`) and
before deploys (`trigger-main.yaml` / `trigger-release.yaml`).

## Conventions

- Use `severity: error` for rules that must block (e.g. missing tags break `--select-tag` scoping).
- Use `severity: warn` for advisory rules while they mature, then promote to `error`.
- Keep the set small and high-signal; every rule should catch a real, recurring mistake.
