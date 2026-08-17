# Platform conventions

This page is the cross-language reference contract for identifiers, time, money, correlation, and
errors in a generated repository. It applies to every language and application surface. A language
may choose its idiomatic library and runtime adapter, but its observable representation and
behavior must follow this contract. One JavaScript implementation may serve browser and Node
runtimes through separate adapters.

## Identifiers

Every entity identifier uses UUIDv7 in storage and a TypeID on the wire and in logs. A TypeID is a
lowercase entity prefix, an underscore, and the 26-character Crockford base32 encoding of the same
128-bit UUID. For example:

```text
order_01h455vb4pex5vsknk084sn02q
```

UUIDv7 gives identifiers time ordering and RFC 9562 gives generation and storage a stable
cross-language basis. The TypeID suffix is reversible; services decode it to recover the UUID
storage key. There is no mapping table or second identifier column.

The prefix is declared once beside the entity definition in the interface contract that owns the
entity. That declaration is authoritative: an undeclared prefix is invalid, and declaring the same
prefix for two entities is a contract-verification failure. Prefixes are not allocated in a
central registry separate from the entities they describe.

Each implementation proves the same UUID ↔ TypeID fixture table, including nil and maximum UUIDs,
an undeclared prefix, an uppercase suffix, a wrong-length suffix, and a suffix representing more
than 128 bits. A generated identifier must use this format and ordering scheme even when the
implementation library is different.

Identifiers that must be unguessable, such as password-reset tokens or share links, are separate
security-sensitive values and do not use this convention.

## Time and dates

An instant is an RFC 3339 / ISO 8601 timestamp in UTC with millisecond precision and a `Z` suffix:

```text
2026-07-26T14:30:00.123Z
```

It is stored in a timezone-aware column such as `timestamptz` or its equivalent. Local times and
bare offsets do not cross a service boundary. A client converts UTC to a person's timezone only at
the presentation layer.

A calendar date is a distinct type: an ISO 8601 `YYYY-MM-DD` value with no time and no timezone.
Birth dates, invoice periods, and delivery dates are dates, not instants. Converting between the
two requires a timezone supplied by the caller; neither type silently becomes the other.

Durations and elapsed measurements are not instants and need a purpose-named representation outside
this convention. A stack that needs precision beyond milliseconds carries it in such a purpose-
named field rather than silently changing the general timestamp contract.

## Money and rates

Money is never represented as a floating-point value in memory, storage, or transport. The two
contract types below are distinct so a unit price cannot be passed where a charge is expected.

`Money` is an integer count of a currency's minor unit and an ISO 4217 alphabetic currency code:

```json
{ "amount": 1999, "currency": "USD" }
```

The example is 1,999 cents, or $19.99. The currency code determines the minor-unit exponent; a
value does not carry a separate scale field.

`MoneyRate` is an integer count of micros with a fixed scale of 6 and a currency code when the rate is
monetary:

```json
{ "amount": 3459000, "currency": "USD" }
```

The example is $3.459 per unit. Scale 6 covers ordinary unit prices, FX majors, and CPM-style
rates without making every consumer negotiate a per-value scale. Higher-precision asset amounts
and unresolved multi-currency FX quotes are separate future contracts.

Multiplying a `MoneyRate` by a quantity produces a `Money`. The conversion rounds half-even (banker's
rounding) by default. A domain that must follow a jurisdiction-specific half-up rule states that
override at the conversion point. No implementation may change the scale or rounding mode
silently.

## Correlation

One opaque correlation identifier links logs, spans, errors, and background jobs. It is not the
trace ID and is not a TypeID: tracing can be sampled or dropped at an external hop, and ingress
infrastructure may mint an identifier without knowing the repository's entity prefixes.

At every admission boundary — an inbound request or a dequeued job — the service:

1. Adopts an inbound `x-request-id` when it passes the length and character-class checks.
2. Mints a UUIDv7 when no well-formed identifier is present.
3. Propagates the adopted or minted value unchanged on every outbound call and enqueue.

The value is opaque. Validation rejects control characters and whitespace and enforces a bounded
length, but a service does not inspect the value's structure, use it for authorization, or reassign
it between hops. It appears in logs as `request_id`, alongside `trace_id` and `span_id`, and rides
in job metadata. `traceparent` remains the complementary tracing propagation mechanism.

## Errors

Every surfaced failure uses one error value. HTTP renders it as `{ "error": { ... } }`; a job
records the same value on its failure record; and a CLI prints it and maps its `code` to an exit
status. The rendering changes with the surface, not the contract.

The value contains:

- `code`: a stable `SCREAMING_SNAKE_CASE` classification. Platform-wide conditions use reserved
  unprefixed codes such as `INTERNAL_SERVER_ERROR` and `REQUEST_ERROR`; service-specific codes use
  a domain prefix such as `BILLING_CARD_DECLINED`.
- `message`: human-readable text safe to show to the caller.
- `remediation`: what would resolve the failure.
- `correlationId`: the correlation value from the admission boundary.
- `retryable`: whether this particular failure is safe to retry. Retry policy remains owned by
  runtime resilience.
- `details`: optional caller-visible structured data. Each error case declares its shape in the
  error catalog, and generated case types carry that shape into every language implementation.
- `diagnostics`: optional stack and original unredacted message, controlled by the setting below.

Unexpected failures are redacted to `INTERNAL_SERVER_ERROR`; internal detail is withheld from the
caller and logged with the correlation identifier. The envelope preserves the `error` nesting so
all surfaces can classify failures without reading the implementation that raised them.

## Diagnostics and disclosure

The stack is always captured and always logged. Only its inclusion in the value rendered to a
caller is conditional. `ERROR_DIAGNOSTICS_ENABLED` is a validated configuration setting, defaults
to `false`, and fails closed: an absent, malformed, misspelled, or otherwise invalid setting never
discloses `diagnostics`. Services do not infer this setting from an environment name such as
`NODE_ENV`. When explicitly enabled, `diagnostics` includes the stack and the original unredacted
message; otherwise the caller receives the safe error value while operators use the logs.

## Conformance fixtures

A per-language implementation is non-conformant until it passes every applicable fixture below.
The first language implementation owns the runner shape; later implementations assert the same
observable results.

| Fixture                       | Required observable result                                                                                                                                             |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| UUID ↔ TypeID boundary pairs | Nil and maximum UUIDs round-trip, and UUIDv7 TypeIDs preserve the lowercase prefix and 26-character suffix format.                                                     |
| Invalid TypeID                | Undeclared prefixes, uppercase suffixes, wrong-length suffixes, and values wider than 128 bits are rejected.                                                           |
| Instant                       | A timestamp is stored and emitted as UTC RFC 3339 with millisecond precision and `Z`; a local offset is not emitted.                                                   |
| Calendar date                 | `YYYY-MM-DD` round-trips without a time or timezone and does not shift across a timezone boundary.                                                                     |
| Money and MoneyRate           | Integer amounts and ISO currency codes round-trip without floating-point conversion; MoneyRate-to-Money uses half-even rounding.                                       |
| Correlation adoption          | A valid inbound `x-request-id` is preserved unchanged; an invalid or absent value is replaced by a minted UUIDv7.                                                      |
| Correlation propagation       | The same value appears in outbound headers, job metadata, `request_id` log fields, and the error's `correlationId`.                                                    |
| Error redaction               | An unexpected failure has a stable code, remediation, retry signal, and correlation ID; stack and original message appear only when validated diagnostics are enabled. |

## Naming

Every name that crosses a service boundary follows one declared rule for its boundary kind. The
policy stops at the wire: a stack maps a boundary name into its own idiom (Go exports `OrderID`,
Python and Rust write `order_id`, TypeScript keeps `orderId`), and the mapping is a mechanical,
lossless function of the boundary name, so the wire form never varies with the language that
produced it. Code-internal naming is otherwise unconstrained by this policy.

| Boundary                                       | Rule                                                                     | Example                                          |
| ---------------------------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------ |
| JSON body fields, event payloads, job metadata | `camelCase`                                                              | `retryable`, `correlationId`                     |
| Log and metric attribute keys                  | `snake_case`                                                             | `request_id`, `trace_id`                         |
| Enum values on the wire                        | `SCREAMING_SNAKE_CASE`                                                   | `PAST_DUE`                                       |
| Error codes                                    | `SCREAMING_SNAKE_CASE`; unprefixed reserved for platform-wide conditions | `INTERNAL_SERVER_ERROR`, `BILLING_CARD_DECLINED` |
| Schema component and generated type names      | `PascalCase`                                                             | `Money`, `ErrorEnvelope`                         |
| URL path segments                              | lowercase `kebab-case`, plural resource nouns, leading `/vN`             | `/v1/order-lines`                                |
| Path and query parameters                      | `camelCase`, matching body fields                                        | `orderId`                                        |
| HTTP headers                                   | lowercase `kebab-case`; matched case-insensitively on receipt            | `x-request-id`                                   |
| OpenAPI vendor extensions                      | `x-archy-<kebab-case>`                                                   | `x-archy-typeid-prefix`                          |
| TypeID prefixes                                | `[a-z][a-z0-9]*`, singular entity noun                                   | `order`                                          |
| Config and secret keys                         | `SCREAMING_SNAKE_CASE`, nesting flattened with `__`                      | `ERROR_DIAGNOSTICS_ENABLED`                      |
| Feature-flag keys                              | lowercase `kebab-case` with `.` namespace separators                     | `billing.new-invoice-flow`                       |

Log and metric attributes are not repository-owned vocabulary: `trace_id` and `span_id` are fixed by
OpenTelemetry, so the correlation value spells differently by boundary — `correlationId` in a body,
`request_id` in a log — rather than forcing one spelling across an externally fixed convention.

Where a boundary matches names case-insensitively, this reference states one canonical written
form, and generated code, contracts, and documentation author that form; a receiver still accepts
any casing that arrives. HTTP headers are the only such boundary here: `x-request-id` is written
lowercase because HTTP/2 and HTTP/3 transmit field names in lowercase and every implementation
already does, while a request bearing `X-Request-Id` still matches.

A boundary name is a term from the repository's shared lexicon combined with a role suffix whose
meaning is fixed by the representation policy above. The suffix keeps its meaning under each
boundary's own casing — the same field is `createdAt` in a body and `created_at` in a log — because
the suffix is part of the term, not the casing:

| Suffix   | Contract type        | Example       |
| -------- | -------------------- | ------------- |
| `Id`     | `TypeID` reference   | `orderId`     |
| `At`     | `Instant`            | `createdAt`   |
| `On`     | `LocalDate`          | `invoicedOn`  |
| `Amount` | `Money`              | `totalAmount` |
| `Rate`   | `MoneyRate`          | `taxRate`     |
| `Count`  | non-negative integer | `itemCount`   |

A boolean is an adjective or past participle with no `is`/`has` prefix (`retryable`, `archived`). A
field whose suffix disagrees with its declared contract type — an `At` field that is not an
`Instant`, an `Id` field that is not a `TypeID` — is a contract-verification failure. One term names
one concept across every boundary; a second term for an already-named concept is an inconsistency to
fix, not a new concept.

A name outside the rule for its boundary is non-conformant unless it appears in the rule set's
exemption list, which is limited to names fixed by a contract this repository does not own: the
error envelope's `error` nesting, the W3C `traceparent` header, and OpenTelemetry's `trace_id` and
`span_id`.

The rule set is declared in `packages/platform-contract/schema/naming-rules.json`, validated by
`naming-rules.schema.json`, and is the single system of record this table is checked against. The
platform contract package ships a validator over the rule set — a programmatic interface and the
`archy-check-naming` command — that a repository's `contract-check` target invokes against its
OpenAPI document and domain error catalog. That enforcement currently covers the contract boundary:
schema, field, parameter, path, header, vendor-extension, and TypeID-prefix names, plus suffix/type
agreement. Log, metric, queue, and topic names follow the same table above and gain their mechanical
check when observability and async-work deliver.

### Naming a new value

| Adding a...       | Casing rule                                                                    | Role suffix if applicable                                                                                      | Enforced today?                                  |
| ----------------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| Contract field    | `camelCase`                                                                    | See the suffix table if the field is a TypeID, `Instant`, `LocalDate`, `Money`, `MoneyRate`, count, or boolean | Yes — `contract-check` via the shipped validator |
| Wire enum value   | `SCREAMING_SNAKE_CASE`                                                         | —                                                                                                              | Yes — `contract-check` via the shipped validator |
| Error code        | `SCREAMING_SNAKE_CASE`, domain-prefixed unless it is a platform-wide condition | —                                                                                                              | Yes — `contract-check` via the shipped validator |
| HTTP header       | lowercase `kebab-case`, authored form even though matching is case-insensitive | —                                                                                                              | Yes — `contract-check` via the shipped validator |
| Configuration key | `SCREAMING_SNAKE_CASE`, `__` for nested keys                                   | —                                                                                                              | No — stated in this table, not yet checked       |

Whichever kind of name is being added, reuse an existing term from this reference or from the
repository's own domain vocabulary rather than inventing a synonym; the casing and suffix rules only
protect a name's form, not whether it duplicates an existing concept under a different word.

## Related decisions

- [ADR 0006 — Standardize cross-cutting representations](../decisions/0006-standardize-cross-cutting-representations.md)
- [ADR 0009 — Name boundary-crossing values](../decisions/0009-name-boundary-crossing-values.md)
- [Production readiness model](../explanation/production-readiness.md)
