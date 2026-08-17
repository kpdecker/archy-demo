# archy-demo — documentation

> This is the documentation knowledge base for archy-demo. It is organized with
> [Diátaxis](https://diataxis.fr), a documentation framework that splits writing into four
> kinds — tutorials, how-to guides, reference, and explanation — each serving a distinct reader
> need. This page is only a map of what exists and where it lives; the pages it links to hold the
> content, and several of them ship as templates that you fill in as the system takes shape.

## Map

| If you want to…                                | Go to                        |
| ---------------------------------------------- | ---------------------------- |
| **Learn** the system by doing                  | [tutorials/](tutorials/)     |
| **Accomplish a specific task**                 | [how-to/](how-to/)           |
| **Look up** facts (APIs, config, commands)     | [reference/](reference/)     |
| **Understand** why things are the way they are | [explanation/](explanation/) |

## Also here

- [architecture.md](architecture.md) describes how this system fits together.
- [reference/application-surfaces.md](reference/application-surfaces.md) defines the application
  surface layout, which is the `app/<name>/<surface>` unit used for every deployable project, along
  with the nx project identity and tags derived from it.
- [reference/configuration-and-secrets.md](reference/configuration-and-secrets.md) defines the
  layered configuration order, startup validation, runtime secret delivery, and feature-flag
  contract.
- [reference/platform-conventions.md](reference/platform-conventions.md) defines identifiers, UTC
  timestamps and dates, integer money and rates, correlation propagation, and the error contract.
- [reference/service-contracts.md](reference/service-contracts.md) defines contract-first OpenAPI,
  generated clients, compatibility verification, versioning, and shared boundary semantics.
- [reference/service-descriptors.md](reference/service-descriptors.md) defines portable workload,
  configuration-name, secret-name, and managed-dependency registration for every deployable surface.
- [reference/deployment-substrates.md](reference/deployment-substrates.md) defines production
  substrate selection, fixed local and ephemeral targets, and promotion signals between rungs.
- [reference/local-development.md](reference/local-development.md) defines the `pnpm dev` entry
  point, the target vocabulary beneath it, the local equivalent guaranteed for every managed
  dependency, and the rules that make seed data reproducible.
- [reference/openspec.md](reference/openspec.md) covers the OpenSpec workflow and how the generated
  OpenSpec skills are kept up to date.
- [decisions/](decisions/) holds the Architecture Decision Records (ADRs), which are short documents
  that capture one decision, the options considered, and the consequences. They follow the MADR
  (Markdown Any Decision Records) format.
- [conventions/](conventions/) collects the coding and git conventions for this repository.
- [glossary.md](glossary.md) defines the domain terms used across these pages.

<!-- AI agents: AGENTS.md at the repo root points here. Keep this map current as docs grow. -->
