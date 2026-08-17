#!/usr/bin/env bash
# scaffold-managed: openspec-skill-patching
# Refresh generated OpenSpec instructions at the pinned version, then restore managed patches.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${1:-$SCRIPT_DIR/../..}" && pwd)"
VERSION_FILE="$ROOT/.scaffold/openspec/version.env"
VERIFY="$SCRIPT_DIR/verify-openspec-skills.sh"
RECONCILE="$SCRIPT_DIR/reconcile-openspec-skills.sh"
BRIDGE="$ROOT/.claude/skills/openspec-sync-specs"

die() { printf '[scaffold-openspec] ERROR: %s\n' "$*" >&2; exit 1; }
[ -f "$VERSION_FILE" ] || die "missing $VERSION_FILE"
# shellcheck disable=SC1090
source "$VERSION_FILE"
[[ "${OPENSPEC_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'invalid pinned OpenSpec version'
command -v pnpm >/dev/null 2>&1 || die 'pnpm is required'
"$VERIFY" "$ROOT"

UPDATE_STAGE="$(mktemp -d "$ROOT/.scaffold/openspec/.update.XXXXXX")"
cleanup() {
  if [ ! -e "$BRIDGE" ] && [ ! -L "$BRIDGE" ] && [ -L "$UPDATE_STAGE/previous-bridge" ]; then
    mkdir -p "$(dirname "$BRIDGE")"
    mv "$UPDATE_STAGE/previous-bridge" "$BRIDGE"
  fi
  rm -rf "$UPDATE_STAGE"
}
trap cleanup EXIT
mv "$BRIDGE" "$UPDATE_STAGE/previous-bridge"

printf '[scaffold-openspec] refreshing OpenSpec instructions with %s\n' "$OPENSPEC_VERSION" >&2
if ! (
  cd "$ROOT"
  pnpm dlx "@fission-ai/openspec@$OPENSPEC_VERSION" update "$ROOT" --force
); then
  die 'OpenSpec update command failed; the previous sync-skill bridge will be restored'
fi
[ -f "$BRIDGE/SKILL.md" ] && [ ! -L "$BRIDGE" ] \
  || die 'OpenSpec update did not generate a fresh sync-skill candidate; the previous bridge will be restored'

"$RECONCILE" "$ROOT"
"$VERIFY" "$ROOT"
