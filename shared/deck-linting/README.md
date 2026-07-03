# deck linting

Linting rules for the generated Kong **deck** (gateway) configuration. This is the deck-level
counterpart to the OpenAPI linting done with Spectral in `validate-apis.yaml`.

`deck file lint` is built on [Spectral](https://stoplight.io/open-source/spectral), so
[`ruleset.yaml`](ruleset.yaml) is a Spectral ruleset — but its `given` JSONPaths target the
decK state file (`$.services`, `$.services[*].routes`, `$.plugins`, …) rather than an OpenAPI
document.

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
