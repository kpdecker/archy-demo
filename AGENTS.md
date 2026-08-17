<!-- repo-boot:project:start -->

# archy-demo

nx (pnpm) monorepo. Deployable surfaces live in `app/<name>/<surface>`, shared libraries in `libs/`.

## Commands

- Install: `pnpm install`
- Run a task: `pnpm nx <target> <project>` (e.g. `pnpm nx build <project>`, `pnpm nx test <project>`)
- Affected only: `pnpm nx affected -t build test lint`
- List projects: `pnpm nx show projects`
- Format all supported files: `pnpm format`; check without writing: `pnpm format:check`
- Lint every project: `pnpm lint`; only what you touched: `pnpm lint:affected`; autofix: `pnpm lint:fix`

## Where things live

- `app/*/*` — deployable surfaces grouped by logical application name (`server`, `browser`,
  `mobile`, `ios`, or `android`). Application-specific code can stay here.
- `libs/*` — reusable libraries (feature / ui / data-access / util), tagged `scope:*` + `type:*`.
  Prefer factoring shareable logic (state machines, domain logic) here so it can be reused and tested.
- `docs/` — knowledge base (Diátaxis). Start at `docs/index.md`; decisions in `docs/decisions/` (ADRs).
- `openspec/` — spec-driven development; propose and apply changes with the `/opsx:*` commands.

## Conventions

- Write in plain language for humans and agents. Use complete sentences with clear subjects and
  verbs in prose — paragraphs, and bullets that carry a claim or an explanation.
- Keep enumerative bullets terse. A bullet that is a label, a bare fact, or a `key — value` pair
  stays a fragment; do not pad it into a sentence. Expand one only when the short form drops a
  connective the reader must reconstruct — a cause, condition, or contrast — or when it reads
  ambiguously. Given two equally clear phrasings, use the shorter.
- Unless a document names another audience, write for a mid-level software engineer. Use standard
  software-engineering terms when they are precise; define project-specific or uncommon terms when
  they first appear.
- Use one consistent term for each concept, and state a page's purpose, scope, and status boundaries
  directly.
- Prefer running tools through nx, not the underlying CLI directly.
- Module boundaries are enforced by project tags (added when the first project is generated).
- Follow [docs/reference/application-surfaces.md](docs/reference/application-surfaces.md) for
  canonical surface paths, nx project names, and tags.
- Refresh generated OpenSpec skills with `scripts/scaffold/update-openspec.sh`; repair or verify
  managed patch state with the adjacent `reconcile-openspec-skills.sh` and
  `verify-openspec-skills.sh` commands. See [docs/reference/openspec.md](docs/reference/openspec.md).
- See `docs/conventions/` for code and git conventions.
- Claude Code and Codex use repository-local post-write hooks to call the formatter. If another
  host has no repository-local write hook, run `pnpm format:paths -- <path>` after changing a
  supported file. The pre-commit hook and CI invoke the same dispatcher, `scripts/format-paths.sh`,
  over staged files and over the whole workspace. No project declares a formatting target.
- Every diagnostic fails a `lint` target; rules come from each language's shared base, not from a
copy in a project. Pushing gates on the lint of what changed; committing does not.
See [docs/reference/code-style.md](docs/reference/code-style.md).
<!-- repo-boot:project:end -->

<!-- nx configuration start-->
<!-- Leave the start & end comments to automatically receive updates. -->

# General Guidelines for working with Nx

- For navigating/exploring the workspace, invoke the `nx-workspace` skill first - it has patterns for querying projects, targets, and dependencies
- When running tasks (for example build, lint, test, e2e, etc.), always prefer running the task through `nx` (i.e. `nx run`, `nx run-many`, `nx affected`) instead of using the underlying tooling directly
- Prefix nx commands with the workspace's package manager (e.g., `pnpm nx build`, `npm exec nx test`) - avoids using globally installed CLI
- You have access to the Nx MCP server and its tools, use them to help the user
- For Nx plugin best practices, check `node_modules/@nx/<plugin>/PLUGIN.md`. Not all plugins have this file - proceed without it if unavailable.
- NEVER guess CLI flags - always check nx_docs or `--help` first when unsure

## Scaffolding & Generators

- For scaffolding tasks (creating apps, libs, project structure, setup), ALWAYS invoke the `nx-generate` skill FIRST before exploring or calling MCP tools

## When to use nx_docs

- USE for: advanced config options, unfamiliar flags, migration guides, plugin configuration, edge cases
- DON'T USE for: basic generator syntax (`nx g @nx/react:app`), standard commands, things you already know
- The `nx-generate` skill handles generator discovery internally - don't call nx_docs just to look up generator syntax

<!-- nx configuration end-->
