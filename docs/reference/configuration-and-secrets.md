# Configuration, secrets, and environments

This page is the reference contract for how a generated service resolves configuration, validates
settings, receives secrets, and evaluates feature flags. It applies across languages and surfaces.
The libraries, typed settings objects, and provider SDKs are implementation choices, but their
observable behavior must follow this contract.

## Resolution order

Services resolve sources from highest to lowest precedence:

1. Secret files under `SECRETS_DIR`, only for keys the schema declares secret.
2. Process environment variables.
3. The environment-specific config file.
4. The base or default config file.
5. Schema-declared defaults.

When a value appears at more than one source, the service selects the highest-precedence source.
Every language uses this order; a loader may not reorder the layers.

Secret keys have two additional rules:

- A key declared secret is never read from the committed environment-specific or base config files.
- A secret key falls back to the process environment only when no secret file exists for that key.

The environment name is explicit input to the loader. A service does not infer precedence from
ambient production or development heuristics.

## Startup validation

Each service declares a native typed schema, including the keys classified as secret. It resolves
all sources and validates the resulting settings before the process accepts work or serves
traffic.

If a required value is missing or has the wrong type, validation exits non-zero before startup
continues. The failure names the offending key and what was expected. Validation and diagnostic
output never contain a configured secret value.

The policy is behavioral rather than structural: JavaScript, Python, Go, and Rust may use their
idiomatic schema libraries, but each implementation must expose the same observable startup and
diagnostic behavior.

## Secret delivery

Non-secret configuration reaches the process through environment variables. Secret material reaches
the process at runtime as one mounted file per key under `SECRETS_DIR`, which defaults to
`/etc/secrets`. The service reads `${SECRETS_DIR}/<KEY>` into its typed settings during startup.

The read path is the same in every environment. A service never branches on whether it runs in
local, ephemeral, or production; only the provisioning behind the path changes. Secret values are
never committed to the repository and never included in a build artifact.

### Local workflow

- `config/secrets.template` is committed and lists required secret key names without values.
- For a run without a cluster, bootstrap creates the gitignored `.secrets/` directory with one file
  per key and points `SECRETS_DIR` at it.
- For a local Kubernetes cluster, `overlays/local` uses a Kustomize `secretGenerator` to build and
  mount the Secret at `/etc/secrets` from those files.

External sandbox credentials remain outside the repository and agent context. If a required value
is absent, startup validation fails fast with the key named until the operator supplies it through
the documented secure channel.

### Substrate obligations

`repo-infra` must satisfy these delivery requirements:

- A ConfigMap supplies non-secret configuration to the process environment.
- A Kubernetes Secret supplies secret files through a mounted volume.
- `ClusterSecretStore` is the single provider-bearing manifest; workload manifests reference the
  provider-neutral Kubernetes Secret rather than a cloud-specific secret manager.
- The cluster provides encryption at rest for Kubernetes Secret data as a precondition.

The external secret manager and its provider-specific identity binding belong to the deployment
substrate. Services consume only the mounted-file contract.

## Feature flags

Feature flags use one evaluation contract:

```text
isEnabled(flagKey, context) -> bool
```

The exact naming follows each language's idiom, but the interface accepts a flag key and evaluation
context and returns whether the flag is enabled. The provider is separate from configuration and
can be re-evaluated without a redeploy. A flag has its own namespace and is not modeled as another
validated settings boolean.

## Conformance expectation table

A language implementation is non-conformant until it passes every row below. The conformance
runner is built with the first per-language implementation in US-2 and drives equivalent fixtures
against each later implementation.

| Fixture                                | Required observable outcome                                                                                                                                               |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Missing required key                   | Exit non-zero before startup; the diagnostic names the missing key and states that a value is required, without printing any secret value.                                |
| Wrong type                             | Exit non-zero before startup; the diagnostic names the offending key and expected type, without printing any secret value.                                                |
| Same key supplied at several sources   | Exit zero and resolve the value from the highest-precedence supplied source: secret file, process environment, environment-specific file, base file, then schema default. |
| Missing secret file                    | If the process environment has no fallback, exit non-zero before startup and name the missing secret key without printing a value.                                        |
| Secret present only in the environment | Exit zero and resolve the secret from the process environment; diagnostics report only safe presence or source metadata and never the value.                              |

## Related decisions

- [ADR 0005 — Deliver secrets as mounted files](../decisions/0005-deliver-secrets-as-mounted-files.md)
- [Production readiness model](../explanation/production-readiness.md)
