## Description

<!-- What does this PR change and why? -->

## Related issue

Closes #

## Type of Change

<!-- Check all that apply. -->

- [ ] New API
- [ ] API feature / change
- [ ] Bug fix
- [ ] Breaking change
- [ ] Documentation update
- [ ] Deprecation
- [ ] Pipeline / tooling

## Breaking Changes

- Does this PR introduce breaking changes to an API? [ ] Yes [ ] No

<!-- If yes: describe the impact + migration, and register the new version in
     apis/<name>/breaking-changes.yaml (CI blocks otherwise). -->

## Versioning

<!-- Only if a spec changed. Bump apis/<name>/openapi-spec info.version (semver). -->

- Current version: `x.y.z`
- New version: `x.y.z`

## Pre-merge checklist

<!-- CI (validate.sh) fails the PR if these aren't met when a spec changes. -->

- [ ] `apis/<name>/changelog.md` last line updated to match the spec `info.version`
- [ ] Version bumped (valid semver) if the OpenAPI spec changed
- [ ] Breaking changes registered in `apis/<name>/breaking-changes.yaml`
- [ ] Spectral + deck lint pass locally (`cd scripts && make validate build lint APP=<name>`)
- [ ] New API? added to the app list(s) in `trigger-main.yaml` / `trigger-release.yaml`, and `konnect.yaml` present

## Compatibility

<!-- Backward-compatibility notes for existing clients, if any. -->
