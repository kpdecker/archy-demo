# How to add a microservice

This guide shows you how to add a backend service to this monorepo, run it, and place feature code
inside a Node service. It does not cover deployment or infrastructure. Everything described here
works today.

The default stack is **Node + Fastify**, and **Python (FastAPI)**, **Go (chi)**, and **Rust (axum)**
are also supported. A service lives at `app/<name>/server`, which is an application surface: the
`app/<name>/<surface>` unit this repository uses for each deployable project. Every service joins
the nx graph, the project dependency graph nx derives from the repository, with the standard build,
serve, and quality nx targets (the named commands nx can run for a project) and the nx tags
`scope:<name>`, `type:app`, and `platform:server`.

## Steps

1. Ask your assistant to add the service, which it does with the `repo-microservice` skill. For
   example, say _"add a Go microservice named gateway"_, or _"add a service called orders"_ to get
   the Node default.

2. For a service that is not Node, the assistant first checks that the language toolchain is
   installed (Go, Rust, or `uv` for Python). If the toolchain is missing, the assistant shows you
   the exact install command and asks before running it, so nothing is installed without your
   go-ahead.

3. Run the new service:

   ```bash
   pnpm nx serve <name>-server     # start it
   pnpm nx build <name>-server     # build it
   pnpm nx test  <name>-server     # test it
   pnpm nx lint <name>-server      # lint it
   pnpm nx typecheck <name>-server # typecheck it — Node and Python; Clippy and go vet type-check as part of Rust's and Go's lint
   pnpm format:check               # check formatting; formatting is workspace-wide, not per project
   ```

   Node, Go, Rust, and Python services expose a health check at `GET /healthz`.

## Add a Node feature

Node services keep process startup in `src/main.ts` and Fastify composition in `src/app.ts`. Add
feature code only in the layers it needs, using role-suffixed names and colocated `*.test.ts` files:

```text
src/routes/status.routes.ts       # Fastify request/reply handling
src/services/status.service.ts    # plain TypeScript business logic
src/schemas/status.schema.ts      # Zod request/response schema + inferred types
```

`status.routes.ts` imports the schema and the service, and `status.service.ts` never imports
Fastify. If the feature later needs persistence, add `src/repositories/status.repository.ts` and
inject it into the service, which preserves the `routes -> services -> repositories` direction. Do
not create an empty repository layer. Put helpers shared by features in `src/shared/`, and move them
to `libs/` only once several application surfaces can reuse them.

## Add a Rust feature

Rust services keep process startup (tracing, configuration, the listener, bounded shutdown) in
`src/main.rs` and router composition in `src/app.rs`, behind `build_router(&Config) -> Router` —
tests drive it with `tower::ServiceExt::oneshot` instead of binding a port. Add feature code only in
the layers it needs, one file per feature per layer, with colocated `#[cfg(test)] mod tests`:

```text
src/routes/status.rs       # axum handler and Router construction — the only layer that imports axum
src/services/status.rs     # plain Rust business logic; no axum import
src/schemas/status.rs      # serde request/response types
```

Declare each layer module file the first time it holds content (`pub mod status;` in `routes.rs`,
`services.rs`, `schemas.rs`), and merge the feature's router into `build_router` in `src/app.rs`.
`routes/status.rs` imports the schema and the service; `services/status.rs` never imports axum. If
the feature later needs persistence, add `src/repositories/status.rs` and inject it into the
service, which preserves the `routes -> services -> repositories` direction. Do not create an empty
layer module. Put helpers shared by features in `src/shared/`, and move them to `libs/` only once
several application surfaces can reuse them.

Every generated Rust crate is a member of one workspace-root `Cargo.toml`, which owns the shared
`Cargo.lock`, `/target` build directory, edition, and dependency versions — run `cargo build`,
`cargo test`, and `cargo clippy` for one service with `-p <crate>` rather than expecting a
per-service lockfile. A generated Rust service is **not yet on the shared cross-language error
contract**: it ships no error-rendering module, so an unexpected failure returns whatever axum
returns by default rather than the platform error envelope. That lands with a future Rust error
crate; until then, do not treat a default `500` response as conformant with the shared contract.

## Add a Python feature

Python services keep process startup (configuration, uvicorn, bounded shutdown) in `src/<module>/
main.py` and application composition in `src/<module>/app.py`, behind `create_app() -> FastAPI` —
tests drive it with FastAPI's `TestClient` instead of binding a port. Add feature code only in the
layers it needs, one file per feature per layer, with colocated `test_<feature>.py`:

```text
src/<module>/routes/status.py       # FastAPI handler and APIRouter construction — the only layer that imports FastAPI
src/<module>/services/status.py     # plain Python business logic; no FastAPI import
src/<module>/schemas/status.py      # Pydantic request/response models
```

`routes/status.py` imports the schema and the service; `services/status.py` never imports
FastAPI. If the feature later needs persistence, add `src/<module>/repositories/status.py` and
inject it into the service, which preserves the `routes -> services -> repositories` direction. Do
not create an empty layer package. Put helpers shared by features in `src/<module>/shared/`, and
move them to `libs/` only once several application surfaces can reuse them.

Every generated Python package is a member of one workspace-root `pyproject.toml`, which owns the
shared `uv.lock`, `.venv`, and `[tool.mypy]` configuration — run `uv add` from the service
directory to add a dependency, and run `nx typecheck`, never a bare `mypy`, since mypy does not
discover the workspace configuration on its own from a service directory. A generated Python
service is **not yet on the shared cross-language error contract**: it ships no error-rendering
module, so an unexpected failure returns whatever FastAPI returns by default rather than the
platform error envelope. That lands with a future Python error package; until then, do not treat a
default `500` response as conformant with the shared contract.

## Add a Go feature

Go services keep process startup (logging, configuration, the listener, bounded shutdown) in
`main.go` and router composition in `internal/app/app.go`, behind `BuildRouter() http.Handler` —
tests drive it with `net/http/httptest` instead of binding a port. Feature layers live under
`internal/`, which the Go toolchain makes importable only from inside this service's module. Add
feature code only in the layers it needs, one file per feature per layer, with colocated
`<file>_test.go`:

```text
internal/routes/status.go       # chi handler and route registration — the only layer that imports chi
internal/services/status.go     # plain Go business logic; no chi or net/http import
internal/schemas/status.go      # request/response types and their JSON tags
```

Each feature file in `internal/routes/` exposes one `Mount<Feature>(chi.Router)` function, and
`BuildRouter` calls it — that is what lets two features register root-level paths without colliding.
`routes/status.go` imports the schema and the service; `services/status.go` never imports chi. If the
feature later needs persistence, add `internal/repositories/status.go` and inject it into the
service, which preserves the `routes -> services -> repositories` direction. Go enforces that
direction for you: a `services` package that imports `routes` fails to build with an import-cycle
error. Do not create an empty layer package. Put helpers shared by features in `internal/shared/`,
and move them to `libs/` only once several application surfaces can reuse them.

Each Go service is its own module with its own `go.mod` and `go.sum`; there is no repository-root Go
workspace file, unlike Rust's shared `Cargo.toml`. A generated Go service is **not yet on the shared
cross-language error contract**: it ships no error-rendering package, so an unexpected failure
returns whatever chi and `net/http` return by default rather than the platform error envelope. That
lands with a future Go error library; until then, do not treat a default `500` response as conformant
with the shared contract.

## Notes

- **Default framework per language:** Node → Fastify, Python → FastAPI, Go → chi, Rust → axum.
- **Where it lands:** `app/<name>/server`, registered as `<name>-server` and tagged `scope:<name>`,
  `type:app`, `platform:server`.
- **Node structure:** `src/main.ts`, `src/app.ts`, typed `src/config/env.ts`, framework integration
  under `src/plugins/`, and role-suffixed feature files under `src/routes/`, `src/services/`,
  `src/schemas/`, and an optional `src/repositories/`.
- **Rust structure:** `src/main.rs` (process), `src/lib.rs` (crate root), `src/app.rs`
  (`build_router`), typed `src/config.rs`, and layer directories `src/routes/`, `src/services/`,
  `src/schemas/`, and an optional `src/repositories/` — every generated crate joins one
  workspace-root cargo workspace.
- **Python structure:** `src/<module>/main.py` (process), `src/<module>/app.py`
  (`create_app`), typed `src/<module>/config.py`, and layer directories `src/<module>/routes/`,
  `src/<module>/services/`, `src/<module>/schemas/`, and an optional `src/<module>/repositories/`
  — every generated package joins one workspace-root uv workspace.
- **Go structure:** `main.go` (process) at the module root, with `internal/app/` (`BuildRouter`),
  typed `internal/config/`, and layer packages `internal/routes/`, `internal/services/`,
  `internal/schemas/`, and an optional `internal/repositories/` — each service is a standalone
  module with no repository-root workspace file.
- **Graph wiring:** non-JS services use `nx:run-commands` in `project.json`, so `nx affected` and
  caching work like any other nx project.
- **Why these defaults:** the Architecture Decision Records in `docs/decisions/` record each choice.
