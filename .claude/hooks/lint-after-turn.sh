#!/usr/bin/env bash
# Claude Code Stop adapter. Lint what this turn affected, once, before the turn ends.
#
# The push gate is the enforcement point; this only moves the same answer earlier, while the work
# is still in the agent's context. It reports and never fixes, and it carries no lint policy —
# the rules live in each ecosystem's base configuration, not in agent context.
set -euo pipefail

output="$(pnpm lint:affected 2>&1)" && exit 0

# A non-zero exit means diagnostics. Put them on stderr so the harness feeds them back to the agent
# rather than ending the turn on a silent failure.
printf '%s\n' "$output" >&2
printf 'Lint failed for the projects this turn affected. Fix them, or run "pnpm lint:fix".\n' >&2
exit 2
