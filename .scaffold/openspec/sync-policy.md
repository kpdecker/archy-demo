<!-- scaffold-managed: openspec-sync-policy -->

# Scaffold OpenSpec sync policy

This file is managed by Scaffold and supplements the generated `openspec-sync-specs` skill.

When a delta or main-spec scenario contains a `- **Criterion**:` field:

- Treat the clean Scenario title, exact namespaced Criterion value, complete Given/When/Then block,
  and any verification-plan fields as one preservation unit.
- Keep the Criterion field as the first scenario body field. Never shorten
  `<initiative>/US-N/AC-N`, move it into the Scenario title, or silently change its namespace.
- For an initiative-delivering change, require the Criterion namespace to match the proposal's
  `delivery.initiative` value.
- After merging, compare every affected delta scenario with its main-spec scenario and fail the
  sync if its Criterion value, title, acceptance steps, or verification plan was lost or changed.

If `<planningHome.root>/scripts/check-product-sdlc.sh` exists, run it from `planningHome.root`
after the comparison. Report a non-zero checker result as sync failure; do not claim success.
