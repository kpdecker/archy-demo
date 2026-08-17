# 1. Record architecture decisions

- Status: accepted
- Date: 2026

## Context and Problem Statement

We need to record the architectural decisions made on this project so that the reasoning behind them
is not lost, and so that newcomers, whether human or AI, can understand _why_ the system is the way
it is rather than only _what_ it does. This decision covers how we record decisions, not which
decisions we make.

## Considered Options

- Keep Architecture Decision Records (ADRs), short documents that capture one decision, the options
  considered, and the consequences, in `docs/decisions/` using the MADR (Markdown Any Decision
  Records) format.
- Keep no formal decision log, and rely instead on commit messages and tribal knowledge.
- Keep a single freeform `DECISIONS.md` file.

## Decision Outcome

Chosen: **ADRs in MADR format**, because they are lightweight, they are versioned alongside the
code, and they record the _options considered_, which is exactly the context a future reader or
agent needs in order to avoid re-litigating a settled decision.

### Consequences

- Good: decisions and their rationale are discoverable and reviewable in version control.
- Good: people who are onboarding and AI agents both get durable, high-signal context.
- Bad: someone has to write an ADR every time a significant decision is made, which takes
  discipline.

## More Information

To add a decision, copy `adr-template.md` to a new file, number it sequentially, and link any
related ADRs.
