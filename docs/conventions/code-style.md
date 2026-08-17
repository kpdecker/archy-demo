# Code style

This page records the code conventions that a formatter or a linter cannot fully capture.
Formatting itself is automated through `pnpm format` and checked without writes through
`pnpm format:check`, so run the toolchain instead of hand-formatting. Both commands dispatch through
`scripts/format-paths.sh`, which picks a formatter from one extension table — Prettier for compatible
web, configuration, and documentation files, Ruff for Python, rustfmt for Rust, and gofmt for Go —
without consulting the nx project graph, so no project declares a formatting target.
These conventions apply to all code in this repository and are in force today.

- Prefer clarity over cleverness, and match the idioms and naming of the surrounding code.
- Keep modules focused, and give each public module a short comment that explains its intent.
- Run tasks through nx with `pnpm nx <target> <project>` rather than calling the underlying tool
  directly. `<target>` is an nx target, the named command nx runs for a project.
- Factor reusable logic such as state machines, domain logic, data access, and UI into `libs/`, and
  tag those libraries with `scope:*` and `type:*` so they can be shared and tested in isolation.
  Code specific to a single application surface (an `app/<name>/<surface>` project) can live in that
  surface, because applications do not have to be thin.
