# Service contracts

This page is the cross-language reference contract for request/response service interfaces in a
generated repository. It applies to every language and application surface that produces or
consumes a repository-owned JSON-over-HTTP interface.

The interface source of truth, generation guarantee, versioning and deprecation path, contract
verification, and shared validation and serialization semantics are platform policy. Every
language and surface follows those rules. The generator selected for a language and the runtime
binding used by a generated client are implementation choices, provided they preserve the
observable contract defined here.

## Source of truth

Each service interface has one contract-first OpenAPI 3.1 document. The contract is authored,
reviewed, and versioned directly; route annotations or implementation types do not generate it.
Every server boundary, generated client, and validator derives from that document.

Contracts reuse the platform type vocabulary from the installed platform-contract package. The
package exports one JSON Schema 2020-12 document at `@archy-stack/platform-contract/schema`, backed
by `schema/platform-contract.schema.json` in the published artifact. Contract tooling resolves that
package export before evaluating its JSON Pointer. A contract references the exported definitions
instead of redefining them:

```yaml
$ref: '@archy-stack/platform-contract/schema#/$defs/Instant'
```

The same rule applies to `TypeID`, `Instant`, `LocalDate`, `Money`, `MoneyRate`, and `ErrorEnvelope`.
The vocabulary version is the service's exact platform-contract package dependency pin. A contract
does not declare a second vocabulary version or copy a vocabulary definition inline.

Each entity schema declares its lowercase TypeID prefix once with
`x-archy-typeid-prefix`. That entity-local declaration satisfies the
[platform-conventions](platform-conventions.md#naming) prefix rule. An undeclared prefix or a prefix
declared for more than one entity is a contract-verification failure.

Every schema, field, parameter, path, header, and vendor-extension name a contract declares follows
the [platform-conventions naming policy](platform-conventions.md#naming). A contract describing an
interface this repository does not own declares `x-archy-external: true` at its document root and is
exempt from name validation while remaining subject to every other contract check.

## Project layout

The contract for service `<name>` is an Nx project at `app/<name>/contract` with identity
`<name>-contract` and tag `type:contract`. The producer's server and every generated client depend
on this project rather than placing the contract inside one language's server project.

A generated client lives at `libs/clients/<name>/<language>` with Nx identity
`<name>-client-<language>`. The contract project declares which language clients it generates.
A hand-maintained client for an interface that the contract can cover is a defect.

## Generation and typed boundaries

Generated clients, server-side boundary types, and validators are committed to the repository.
Every generated tree carries a generated-from header naming the contract and its version and states
that the tree must not be edited by hand.

The contract project exposes a `contract-check` target. It regenerates every declared output and
fails when the resulting working tree differs from the committed tree. Generation therefore
remains reviewable while drift fails in CI.

Generated server code preserves the strongest boundary types each supported stack can enforce:

- Node registers generated schemas through a Fastify type provider. Handler `body`, `params`,
  `query`, and reply types come from the contract, so a handler that disagrees with an operation
  fails to compile.
- Python exposes generated typed request and response models, validates them at the boundary, and
  enforces their annotations through the standard `typecheck` target.

Server and client generation map the shared vocabulary faithfully. `TypeID`, `Instant`, and
`LocalDate` do not erase to plain strings in public types, and `Money` is never accepted, stored,
or returned as a floating-point amount.

## Versioning and deprecation

Every operation path carries a major version segment from its first release, such as `/v1/orders`.
Changes within that version are additive: new operations, optional request fields, and response
fields are allowed when the compatibility gate classifies them as non-breaking.

A breaking change ships at a new-versioned path alongside the old operation. The old operation is
marked `deprecated: true`, declares `x-archy-sunset: <date>`, and includes a migration note in
its description. The default sunset is 90 days; a contract may choose a longer period, never a
shorter one.

An operation may be removed only after its sunset date has passed and no in-repository consumer
references it. Deprecated-with-sunset is the only state from which removal is legal.

## Contract verification

Contract verification combines three mechanisms:

- In-repository verification regenerates committed clients and boundary code in the producer's
  change. Nx affected detection then builds and tests every consumer against those outputs. An
  incompatible producer or consumer change fails that build.
- The producer-side compatibility gate diffs the contract against its last released baseline from
  a trusted Git ref using the repository's pinned checker. A breaking diff that does not use the
  versioning and deprecation path fails the producer's build.
- The naming validator shipped by the platform contract package — a programmatic interface and the
  `archy-check-naming` command — checks every name the contract and its domain error catalog declare
  against the [platform-conventions naming policy](platform-conventions.md#naming). The producer's
  `contract-check` target invokes it; a non-conformant name fails that build with the name, its
  boundary kind, and the violated rule reported.

All three mechanisms run before release. Runtime discovery in an environment is not an acceptable
compatibility check.

## Validation and serialization

Every stack enforces these semantics at its service boundary:

- Producers reject unknown request fields.
- Consumers ignore unknown response fields.
- An absent optional field and an explicit `null` are distinct. `null` is valid only where the
  schema allows it.
- A required empty collection is `[]`, never `null` or absent.
- Vocabulary values validate exactly as [platform conventions](platform-conventions.md) defines
  them, including TypeID prefixes, instant precision, calendar dates, and integer money and rates.
- A request validation failure renders the shared error value with code `REQUEST_ERROR` and the
  catalog-declared details object: the request location plus caller-safe path, code, and message
  entries for each failed constraint. It derives from `BAD_REQUEST`, so clients may handle it as
  either the specialized validation failure or a generic bad request.

## Conformance fixtures

Every stack asserts the same boundary fixture cases:

- Unknown request fields are rejected.
- An absent optional field and `null` produce distinct results.
- A required empty collection round-trips as `[]`.
- An instant with excess precision is rejected or normalized exactly as the shared fixture states.
- A TypeID whose prefix does not match `x-archy-typeid-prefix` is rejected.

These cases extend the representation rows in the platform-conventions fixture table stored in the
same packed vocabulary schema. They do not form a second table. Every fixture has one stable
identifier and one expected observable result that each language runner reports.

## Generated client contract

Every generated client:

- exposes one typed operation for each contract operation;
- maps the shared vocabulary to its declared representations;
- decodes a non-success response into a typed error carrying `code`, `retryable`, and
  `correlationId`, plus catalog-generated `details` when that error case declares them;
- imports that typed error and the vocabulary types from the platform-contract package instead of
  emitting copies per contract; and
- propagates the caller's correlation identifier as `x-request-id` on every request.

The HTTP library, synchronous or asynchronous API shape, and other runtime binding details remain
implementation choices for each generated language client.

## Related references

- [Platform conventions](platform-conventions.md)
- [Production readiness model](../explanation/production-readiness.md)
