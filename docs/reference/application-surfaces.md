# Application surfaces

This page is the reference for the application surface layout, the `app/<name>/<surface>` unit that
every deployable project in this repository uses. It defines the standard surfaces and the nx
project name and nx tags derived from each path. It does not explain how to create a project; the
how-to guides cover that. The layout described here is in force today and applies to every
deployable project.

Deployable projects use a two-level application layout:

```text
app/<name>/<surface>
```

`<name>` is a stable logical application boundary. It can represent an internal capability
(`identity`), a service family, or a user-facing application (`customer-portal`); it does not imply
a product, business-domain, team, or ownership taxonomy.

Bridge wiring configures this repository's own agent tooling; shipping agent tooling to another repository is the agent surface's job, not the bridge wiring's.

## Standard surfaces

| Surface   | Use for                                                       | Example                       |
| --------- | ------------------------------------------------------------- | ----------------------------- |
| `server`  | HTTP services, workers, and other server-side deployables     | `app/identity/server`         |
| `browser` | Browser-delivered applications                                | `app/customer-portal/browser` |
| `mobile`  | One intentionally shared iOS/Android codebase such as Expo    | `app/customer-portal/mobile`  |
| `ios`     | An iOS-specific application                                   | `app/customer-portal/ios`     |
| `android` | An Android-specific application                               | `app/customer-portal/android` |
| `agent`   | Code that runs inside an agent harness another party operates | `app/customer-portal/agent`   |

Do not invent a surface for one project. Establish any new stable surface in the shared scaffold
convention and tooling first. Native `ios/` and `android/` build directories emitted inside a shared
`mobile` project remain implementation details of that project.

## Non-surface projects

An application directory may also hold a **non-surface project**: a project that belongs to one
application boundary but is not a deployable surface, and is therefore never tagged `type:app` or
`platform:<surface>`. The surface list above stays closed; a non-surface project is declared here
rather than added to it.

| Project    | Root                  | nx project name   | nx tags                         |
| ---------- | --------------------- | ----------------- | ------------------------------- |
| `contract` | `app/<name>/contract` | `<name>-contract` | `scope:<name>`, `type:contract` |

`contract` is the only non-surface project today. It holds the authored OpenAPI document for the
application's service interface and the declaration of the outputs generated from it, as
[service contracts](service-contracts.md) defines. It sits beside the server rather than inside it
so that a generated client depends on the contract alone, not on the producer's application project.

Add a non-surface project the same way you would add a surface: establish it in the shared scaffold
convention and tooling first, then use it. Do not invent one for a single project.

## Which surface?

The surface follows who runs the process, not what the code does. An agentic backend service that
the team deploys and operates is a `server` surface, even when it runs an agent loop. An MCP server
the team deploys and operates is also a `server` surface, even when an agent is its only consumer:
being consumed by an agent does not determine the surface. A plugin loaded by an agent harness that
another party operates is an `agent` surface.

## nx identity and tags

Derive the identity of every surface the same way:

- **Root directory:** `app/<name>/<surface>`.
- **nx project name:** `<name>-<surface>` (the name nx uses to run targets against it).
- **nx tags:** `scope:<name>`, `type:app`, `platform:<surface>`.

The explicit surface suffix keeps project identity stable when another surface is added later. An nx
tag is a label nx uses to enforce dependency boundaries, and `scope:<name>` is an nx dependency
boundary only. Separate tags can model ownership or business
taxonomy if those concerns are introduced later.

Reusable cross-application code remains under `libs/`. Code specific to one surface can stay in its
surface project; applications do not have to be artificially thin.
