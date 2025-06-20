# Kongtopia

Home to Alice and Bob

## Monorepo Folder Structure

### `apis/`
Contains all individual API configurations, each in its own subfolder:

- **`additions/`**: Configuration elements to be added to the generated decK file.
- **`deck-file/`**: Placeholder for decK files generated from the OpenAPI spec during the CI/CD pipeline.
- **`env-vars/`**: Environment-specific (dev, test, staging, prod) and API-specific variables, used in combination with patches.
- **`md-file/`**: API documentation files. *(May require updates for Dev Portal v3 compatibility.)*
- **`openapi-spec/`**: The OpenAPI specification – the single source of truth for the API contract. Should be kept clean and accurate.
- **`patches/`**: Patches applied to the generated decK file, used alongside `env-vars/`.
- **`plugins/`**: Plugin configurations for the API, optionally referencing shared templates from `common/plugin-templates`.

### `common/`
Holds shared configurations that are **environment-specific** but **not API-specific**:

- **`env-vars/`**: Environment-specific variables, used with patches.
- **`patches/`**: Common patches applied to decK files, driven by environment variables.
- **`plugin-templates/`**: Reusable plugin templates. Define shared plugin configurations across APIs.

### `global/`
Contains configurations that apply across all APIs:

- **`deck-file/`**: Global decK files defining shared resources (e.g., plugins, consumers, certificates). These can be referenced from API-specific pipelines using [decK’s tag-based partial configuration and foreign keys](https://developer.konghq.com/deck/gateway/tags/#partial-configuration-and-foreign-keys).
- **`env-vars/`**: Environment-specific and global variables, used with patches.
- **`patches/`**: Patches applied to the global decK file, also driven by environment variables.
