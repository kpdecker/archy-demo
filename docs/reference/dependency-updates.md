# Dependency updates

This page states this repository's dependency-update policy and names the file that encodes it.
It applies to every dependency in every ecosystem this repository carries: npm, Cargo, PyPI, and
Go modules alike.

## The policy

- **Exact versions.** Every dependency is pinned to one exact version, never a range. A range
  would let the update bot widen a declaration instead of proposing a version bump, trading a
  visible, reviewed change for an invisible resolution change the next install could pick up
  silently.
- **One weekly cadence.** Every update — first-party and third-party alike — is proposed on the
  same weekly schedule, so updates arrive as a small, predictable, reviewable batch rather than
  scattered across the week.
- **Lockfile maintenance.** On the same schedule, the update bot also refreshes each ecosystem's
  lockfile even when no manifest version changes, so a transitive dependency does not go stale
  between direct-dependency bumps.
- **Always reviewed.** No update — first-party or third-party, patch or major — merges on its own.
  Every proposal is a pull request a person reviews and merges by hand.

## What moves first-party dependencies

Every `@archy-stack/*` npm package, `archy-*` Cargo crate and PyPI distribution, and
`github.com/kpdecker/archy/packages/*` Go module in this repository is exempt from the update
bot's ordinary per-ecosystem registry lookup. Those packages move only to the version recorded at
the Archy platform's own gated release — the same one [`.archy/platform.env`](../../.archy/platform.env)
records and `scripts/apply-platform-version.sh` enforces — never to whatever a registry happens to
publish next. See
[`../decisions/`](../decisions/) and the repository's own `AGENTS.md` `repo-boot` project block for
where that record lives and what it means. `repo-upgrade` moves this repository to a newer platform
version by hand; the update bot proposes the same move automatically, on its weekly schedule, as one
pull request that advances every recorded version together and rewrites every manifest through
`scripts/apply-platform-version.sh`.

## The encoding

[`renovate.json`](../../renovate.json) at the repository root is this policy's single source: the
`rangeStrategy`, `schedule`, `lockFileMaintenance`, and `automerge` fields encode the four rules
above, and its `packageRules` and `customManagers`/`customDatasources` encode which packages are
first-party and where their versions come from.
[`.github/workflows/renovate.yml`](../../.github/workflows/renovate.yml) runs the update bot on
that schedule, with the same read credentials the generated CI already holds for the private npm
scope, the Cloudsmith Python index, and the private Go modules.

## Changing the policy

Edit `renovate.json` directly. It is a plain, git-tracked file: a team that wants a different
cadence, a different review rule, or a narrower or wider set of exempted first-party packages edits
it the same way it edits any other configuration file, and the change ships in the next pull request
like any other. Once edited, `repo-boot`'s recipe tooling reports the file as owned by this
repository rather than by the Scaffold plugin, so a later plugin release never overwrites a
deliberate change here.
