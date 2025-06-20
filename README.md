# Kongtopia

Home to Alice and Bob

## Monorepo folder structure
- **apis**: This is where all the different APIs live in their own folder
    - **additions**: Containing config elements you want to add to the generated decK file
    - **deck-file**: A placeholder folder for the deck files that get generated from the OpenAPI spec during the pipeline run
    - **env-vars**: Environment (dev, test, staging, prod) AND API specific variables, to be used with patches
    - **md-file**: Documentation files for the API (might need to be updated for Dev Portal v3)
    - **openapi-spec**: The OpenAPI spec for the API, this is the source of thruth for the API contract, should be as clean as possible.
    - **patches**: Patches that will be applied to the generated decK file, to be used with env-vars
    - **plugins**: Plugins that will be applied to the generated decK file, can be used with common/plugin-templates

- **common**: This is where common plugins and patches live, which are environment specific but not API specific 
    - **env-vars**: Environment (dev, test, staging, prod) specific variables, to be used with patches
    - **patches**: Patches that will be applied to the generated decK file, to be used with env-vars
    - **plugin-templates**: Templates for plugins that will be applied to APIs, the templated part is the part of the configuration that will be the same for all - APIs

- **global**: This is where the decK file containing the global configurations lives
    - **deck-file**: decK files that contains the global configurations (plugins, consumers, certificates, etc). When global elements (e.g. consumers) need to be referenced from API specific pipelines we can use https://developer.konghq.com/deck/gateway/tags/#partial-configuration-and-foreign-keys
    - **env-vars**: Environment (dev, test, staging, prod) AND API specific variables, to be used with patches
    - **patches**: Patches that will be applied to the decK file, to be used with env-vars
