# OpenSpec

This page is the reference for how OpenSpec is set up in this repository. OpenSpec is the
spec-driven development tooling installed here, meaning that a unit of work is written up as a
specification before the code is written. This page covers where the artifacts live and how the
generated OpenSpec skills are maintained; it does not teach the workflow itself. Everything
described here is installed and working today.

An OpenSpec change is one unit of in-flight work, made up of a proposal, its spec deltas, and its
task list, and all of these artifacts live under `openspec/`. Use the `/opsx:*` agent commands (the
slash commands the generated OpenSpec skills expose, such as `/opsx:propose` and `/opsx:archive`) or
the equivalent `openspec` CLI commands to propose, implement, synchronize, validate, and archive
changes.

## Managed generated skills

Scaffold keeps the OpenSpec-generated skills in `.agents/skills/` and bridges Claude to them through
symlinks under `.claude/skills/`. The generated `openspec-sync-specs` skill carries a versioned
policy hook that is managed under `.scaffold/openspec/`.

Run these repository-local commands from the repository root:

```bash
# Refresh at the Scaffold-pinned OpenSpec version, reapply the reviewed patch, and verify it.
scripts/scaffold/update-openspec.sh

# Repair after a raw `openspec update` or diagnose generated-skill drift.
scripts/scaffold/reconcile-openspec-skills.sh
scripts/scaffold/verify-openspec-skills.sh
```

Reconciliation accepts only the exact pristine or already-patched hash recorded in the active
version's manifest. Unsupported versions and local edits fail without replacing the last valid
canonical skill. Add and test a new patch bundle before you change `.scaffold/openspec/version.env`.
