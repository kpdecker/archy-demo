# Service descriptors

This page defines the version-1 service descriptor carried by every deployable application surface.
The descriptor states portable workload intent once. Deployment substrates render registrations
from it, and local development reads its managed dependencies; neither consumer maintains another
service declaration.

## Location and validation

A deployable surface carries exactly one descriptor:

```text
app/<name>/<surface>/service.json
```

The descriptor's `name` is the surface's Nx identity, `<name>-<surface>`. Its `$schema` points to
`config/schemas/service-descriptor.schema.json`. Validate every descriptor with:

```bash
node scripts/service-descriptors.mjs
```

Validation rejects unknown fields, a name that disagrees with the surface path, duplicate workload
identities, and managed-dependency bindings that do not name a declared configuration key.

## Version-1 fields

| Field                       | Meaning                                                                                   |
| --------------------------- | ----------------------------------------------------------------------------------------- |
| `schemaVersion`             | Descriptor contract version; version 1 is the only accepted value.                        |
| `name`                      | Nx project identity derived from the application-surface path.                            |
| `image`                     | Logical image identity; registries, tags, and digests belong to the substrate or release. |
| `workloads`                 | Non-empty list of `web`, `worker`, or `cron` processes.                                   |
| `configuration.environment` | Non-secret process-environment key names, without values.                                 |
| `configuration.secrets`     | Secret key names delivered through the mounted-file contract, without values.             |
| `managedDependencies`       | Portable dependency kind, selected major version, and configuration bindings.             |

A `web` workload declares `port` and `healthPath`. A `worker` may declare an argv-style `command`.
A `cron` workload declares `schedule` and may declare `command`.

```json
{
  "$schema": "../../../config/schemas/service-descriptor.schema.json",
  "schemaVersion": 1,
  "name": "orders-server",
  "image": "orders-server",
  "workloads": [
    {
      "name": "web",
      "type": "web",
      "port": 3000,
      "healthPath": "/healthz"
    }
  ],
  "configuration": {
    "environment": ["DATABASE_URL", "PORT"],
    "secrets": ["DATABASE_PASSWORD"]
  },
  "managedDependencies": [
    {
      "name": "primary-database",
      "kind": "postgresql",
      "majorVersion": 16,
      "bindings": [
        { "key": "DATABASE_URL", "source": "environment" },
        { "key": "DATABASE_PASSWORD", "source": "secret" }
      ]
    }
  ]
}
```

The dependency's major version is portable intent. Local development owns the matching Docker tag
and digest. A production substrate owns the managed product, plan, region, and provider wiring. Both
write connection values through the declared configuration bindings, so application code uses the
same read path in every environment.

## Generated registration boundary

`nx run infra:generate` validates all descriptors and deterministically replaces only
`infra/deploy/base/`. Files there carry a generated header and are committed for review, but they
are not edited by hand. `nx run infra:validate` runs the equivalent of
`infra:generate --check` and fails when a descriptor and the committed registration differ.

The generated ConfigMap sets `PORT` from each web workload's declared port. It omits other declared
environment keys instead of injecting empty strings, so application defaults remain effective.
Environment overlays or managed-dependency provisioning own values that cannot be derived from the
portable descriptor.

The descriptor contains no Kubernetes, Render, Docker, registry, cloud, secret value, or
environment-specific setting. Those are consumer implementations, not portable service intent.

## Related contracts

- [Application surfaces](application-surfaces.md)
- [Configuration and secrets](configuration-and-secrets.md)
- [Deployment substrates](deployment-substrates.md)
