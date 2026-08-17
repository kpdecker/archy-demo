# Deployment substrates

This page defines how a generated repository selects a production deployment substrate and moves
between the product's operating rungs without redefining its workloads.

## Selection

`infra/substrate.json` is the source of truth for the repository-level production selection:

```json
{
  "schemaVersion": 1,
  "production": "kubernetes"
}
```

Version 1 currently accepts only `kubernetes`. Production selection is explicit repository intent;
it is not inferred from whichever generated files happen to exist and is not selected independently
per service.

Local deployment rehearsal remains k3d, and the ephemeral egress-denied sandbox remains
Kubernetes-based, regardless of the production selection. Those fixed targets do not appear in
`substrate.json`.

## Substrate ladder

| Rung         | Availability                         | Deliberate boundary                                                                               |
| ------------ | ------------------------------------ | ------------------------------------------------------------------------------------------------- |
| Managed PaaS | Planned; not selectable in version 1 | Lowest operations and cost floor; bounded to the provider's managed workload and data products.   |
| Kubernetes   | Available as `kubernetes`            | Higher cost and operational ownership in exchange for custom infrastructure and cluster controls. |

The same CI-built images and [service descriptors](service-descriptors.md) cross the rung boundary.
Promotion does not rename workloads or create a second service definition.

Promote from the managed PaaS rung to Kubernetes when the product needs one or more of:

- a managed dependency the lower rung cannot supply;
- custom networking or infrastructure outside the provider's model;
- scale, region, or placement requirements outside the lower rung's bounds;
- cluster-level security, isolation, scheduling, or operational controls.

Provider preference by itself is not a reason to duplicate workload registration. A new substrate
must render its registration from the same descriptor contract and state its deliberate bounds in
this ladder.

## Kubernetes registration

`nx run infra:generate` derives the Kubernetes base from every `app/*/*/service.json`. The local,
ephemeral, and production overlays specialize that generated base. Use `nx run infra:validate` to
detect stale registration before deployment.

Production image registries and immutable references, environment configuration values, secret
providers, replicas, and resource sizing are substrate inputs. They do not belong in the portable
service descriptor.

For Kubernetes on AWS, Terraform derives one ECR repository per descriptor image identity.
`infra:deploy-prod` reads those repository outputs from the selected production state and combines
them with a CI-produced JSON digest map. It refuses missing identities, mutable tags, and a
non-production Terraform state before it renders or applies the production overlay. The committed
base therefore remains substrate-neutral without allowing an unqualified logical image to reach
production.
