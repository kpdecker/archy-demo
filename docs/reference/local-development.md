# Local development

This page is the reference contract for how a contributor takes a fresh checkout of this repository
to a running system. It applies across every language and every application surface: the entry
point, the target vocabulary beneath it, the guarantee that each cloud dependency has a local
equivalent, and the rules that make seed data reproducible are the same everywhere.

The contract is an obligation on the generators that add projects to this repository, not a
statement that every project already satisfies it. A stack's watch runner, container definition, and
seed program are implementation choices owned by that stack; a generator that adds a stack must make
its choices observe the behavior below.

## Entry point

`pnpm dev` is the one documented command that takes a fresh checkout to a running system. A
contributor needs to know no other command to start, and the command is the same on a first run and
on every later run: it is idempotent, so running it against a repository that is already set up
converges rather than failing or duplicating work.

The host supplies only four prerequisites:

- Git
- Node
- pnpm
- Docker

Everything else the entry point needs, including workspace dependencies, it obtains itself. It does
not assume a prior `pnpm install`, and a contributor who has never run one still reaches a running
system.

### Language toolchains

A repository containing a Go, Rust, or Python service needs that language's toolchain, which is not
a host prerequisite. Acquiring it is `dev-setup`'s job, and it stays inside the one-command flow.

`dev-setup` detects a missing toolchain through the consent-gated `ensure_toolchain.sh` contract,
which by design never installs on its own: it exits 3 and prints an `INSTALL_PLAN: <exact command>`
line naming exactly what would be run. The entry point captures that result, shows the plan, asks
for consent, and on approval re-runs the same contract with `--install` and continues to the next
phase within the same `pnpm dev` invocation. A contributor does not run a second command and then
start over.

Consent is a documented interaction, not an undocumented manual step. Declining it, or running
where nobody can answer, ends the run with the plan named and the phase reported — a stated outcome
rather than a failure to explain itself. Nothing system-visible is installed without an explicit
yes.

## Target vocabulary and phase order

Beneath the entry point the contract fixes four project-scoped Nx targets:

| Target      | Meaning                                                                                                                                    |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `dev-setup` | Idempotent preparation for this project: language dependencies, generated local files, and toolchain version assertions. Never continuous. |
| `migrate`   | Bring this project's schema to head.                                                                                                       |
| `seed`      | Load this project's reproducible dataset. Runs only after `migrate`.                                                                       |
| `dev`       | Run this project with reload-on-edit. Continuous.                                                                                          |

A project participates by declaring the targets it needs, and the entry point discovers
participants from the resolved Nx graph. No project list, manifest, or metadata file records who
participates: target presence is the declaration, so adding a stack later changes only that stack's
project configuration.

`pnpm dev` composes the phases in this order:

```text
dev-setup → backing services → migrate → seed → dev
```

It reports the phase it is running, so a failure names its own cause rather than surfacing as an
opaque failure of the whole command. Each phase stays separately invocable through ordinary Nx
commands, so a contributor who only wants to reseed runs `nx run <project>:seed` without restarting
anything else.

## Host and container split

Application processes run host-native against pinned toolchains. Backing services — the database,
cache, object store, and broker — run as pinned Docker containers.

The split follows from the reload loop: a container image rebuild between an edit and its feedback
is exactly what the edit-to-feedback expectation below forbids, and it also costs a contributor
native debugger attach. Backing services have the opposite profile, because nobody edits Postgres
during a feature, and a pinned image gives version parity and a clean teardown that a
host-installed database does not.

Docker is the supported container runtime. The entry point detects its absence and names Docker,
rather than surfacing a connection failure from a client library. Support for another runtime is a
later compatibility decision, not an implicit promise of this contract.

Docker is required only for the backing-service phase. `build`, `test`, `lint`, `typecheck`, and
`format` all remain usable without it.

### Inner loop versus deployment rehearsal

Two local paths exist and they answer different questions. **The inner loop** is `pnpm dev`: edit
code, get feedback. **Deployment rehearsal** is repo-infra's `nx run infra:up-local`, which runs a
k3d cluster and Tilt to validate that manifests, overlays, and images actually deploy. Deployment
rehearsal is not the inner loop, and a contributor working on product code is not expected to run
it. When repo-infra is installed, `docs/how-to/deploy.md` carries its steps.

## Backing services

Managed dependencies are read from the canonical service descriptor defined in
[service-descriptors.md](service-descriptors.md), for the projects the resolved Nx graph puts in
scope. Local development declares no backing service of its own: there is no workspace list and no
local-development-specific fragment that restates what a descriptor already says.

Two rules keep the local stand-in honest.

**Parity.** The local Docker equivalent runs the same major version of the managed service the
descriptor selects, pinned by tag and digest. A repository whose descriptor selects Postgres 16 does
not develop against Postgres 15. The tag and digest are a local-development implementation detail;
the major version is not.

**Same read path.** The local equivalent is reached through the same configuration keys the service
uses in production, as declared in that dependency's descriptor bindings. The entry point sets the
environment name to `local` and points `SECRETS_DIR` at the gitignored `.secrets/` directory, which
it materializes from the committed `config/secrets.template` with development values. This is the
local workflow that [configuration-and-secrets.md](configuration-and-secrets.md) already specifies.

No local workflow requires a cloud credential to run or test a dependency path, and no service
branches on whether it is running locally. Only the provisioning behind the configuration keys
changes between environments.

## Seed data

Seed data is produced by a committed program with a declared constant seed value. The dataset is a
pure function of the repository revision and that constant, so seed generation reads no wall clock,
draws from no random device, and makes no network call.

Seeding is idempotent: re-running it converges on the same dataset rather than duplicating records.
`seed` runs after `migrate`, so it always loads against a schema at head. Seed data never contains
data derived from production, and a checked-in production extract is not seed data.

Determinism binds the entropy source, not the realism or the volume of the data. A seeded
faker-style generator still produces realistic records, and edge-case rows can be declared
explicitly.

## Edit to feedback

`serve` and `dev` are different targets with different jobs. `serve` runs the built artifact,
production-like, behind an explicit build dependency; it is what deployment paths and smoke checks
want. `dev` runs the project with reload-on-edit and declares Nx's `"continuous": true`, so
`nx run-many -t dev` runs the whole set in parallel and a dependent task can wait on a running
process.

No manual rebuild step sits between an edit and its feedback in any stack.

A project that is not a long-running process satisfies this expectation through a continuous test
target instead. A shared library has no server to reload, but a contributor editing it still needs
feedback without a manual rebuild, and continuous test feedback is that signal.

## Agent legibility

The entry point is advertised in the `## Commands` block of the repository's `AGENTS.md`, so an
agent finds it where it finds every other command.

Failures state their own remedy:

- A missing language toolchain surfaces through the consent-gated `ensure_toolchain.sh` contract
  described under [Language toolchains](#language-toolchains), so the plan is always named before
  anything is installed.
- A missing container runtime names Docker, rather than surfacing as a client connection failure.

## Related contracts

- [Service descriptors](service-descriptors.md)
- [Configuration and secrets](configuration-and-secrets.md)
- [Application surfaces](application-surfaces.md)
- [Deployment substrates](deployment-substrates.md)
