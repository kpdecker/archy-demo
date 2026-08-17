# Code style

> **About this page.** How linting works in this workspace: the targets every project exposes, the
> severity every language is held to, where each ecosystem's rules are decided, and where
> enforcement runs. Formatting is a separate contract; see the formatting section of `AGENTS.md`.

## Targets

Every project exposes two targets, whatever its language:

| Target     | Behavior                                                                  |
| ---------- | ------------------------------------------------------------------------- |
| `lint`     | Reports; never writes. Cacheable, so a re-run over untouched code is free |
| `lint-fix` | Applies the linter's autofix, or reports that the language has none       |

Three commands drive them from the workspace root:

```sh
pnpm lint            # every project
pnpm lint:fix        # every project, applying autofixes
pnpm lint:affected   # only the projects your work touched
```

`pnpm lint:affected` compares against the merge base with the default branch and counts uncommitted
work as touched, so it answers "is what I am working on clean right now".

## Severity

**Every diagnostic fails.** No language keeps a warning tier that exits zero: a rule set that is
identical on paper means nothing if one stack reports its findings and still passes.

Relaxing a rule is legal and is meant to be visible. Add the relaxation to that project's own linter
configuration, layered over the shared base, where it shows up in the diff and can be discussed.
Inline suppressions are each linter's own mechanism — an ESLint disable directive must carry a
description, and an unused one is itself an error.

## Where the rules live

A rule is decided once per language, not once per project. An ecosystem whose linter is useless
without configuration gets a shared base; one whose defaults are already right does not get a file
invented for symmetry.

| Language | Linter   | Base configuration                            | How a project uses it          |
| -------- | -------- | --------------------------------------------- | ------------------------------ |
| JS/TS    | ESLint   | `@archy-stack/lint-config`                    | `eslint.config.mjs` imports it |
| Python   | Ruff     | The workspace `ruff.toml`                     | `pyproject.toml` sets `extend` |
| Rust     | Clippy   | None; the default set denied at `-D warnings` | Nothing to configure           |
| Go       | `go vet` | None; it has no configuration surface         | Nothing to configure           |

Append your own block over a base when a project genuinely needs one. Do not copy the base's rules
into a project: a copy stops receiving changes, and two projects then disagree about the same rule.

**The two bases update differently**, which is worth knowing before you go looking for a change that
has not arrived:

- `@archy-stack/lint-config` is a published package, so a rule change reaches this repository as a
  dependency version bump.
- `ruff.toml` is a checked-in file written when the repository gained its first Python project, so a
  rule change reaches it by regeneration.

Go has no autofix for `go vet` findings; its `lint-fix` target says so rather than pretending.

## Where enforcement runs

| Point      | What runs                                        |
| ---------- | ------------------------------------------------ |
| Commit     | Formatting only — lint does not run              |
| Push       | `lint` for the projects the pushed commits touch |
| CI         | `lint` for affected projects, then all on merge  |
| Agent turn | `lint:affected`, where the harness supports it   |

Lint is deliberately absent from the commit path. Linting is project-granular where formatting is
path-granular, and a commit is the most frequent action in the loop; paying a project's lint cost on
every commit buys nothing for work that is not yet shared. The push is the last moment before CI has
an opinion, so that is where the local gate sits.

Nothing in this chain rewrites your code. Autofix is always something you ask for, because a
linter's fix changes code that runs — unlike a formatter's, which does not.

`git push --no-verify` skips the gate when you need it to; CI still runs.
