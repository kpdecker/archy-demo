#!/usr/bin/env bash
# scaffold-managed: openspec-skill-patching
# Verify the installed OpenSpec sync patch without mutating the repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${1:-$SCRIPT_DIR/../..}" && pwd)"
MANAGED="$ROOT/.scaffold/openspec"
REPAIR='scripts/scaffold/reconcile-openspec-skills.sh'

die() { printf '[scaffold-openspec] ERROR: %s; run %s\n' "$*" "$REPAIR" >&2; exit 1; }
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die 'sha256sum or shasum is required'
  fi
}

[ -f "$MANAGED/version.env" ] || die 'managed version file is missing'
# shellcheck disable=SC1090
source "$MANAGED/version.env"
PATCH_DIR="$MANAGED/patches/${OPENSPEC_VERSION:-missing}"
[ -f "$PATCH_DIR/manifest.env" ] || die "patch manifest for OpenSpec ${OPENSPEC_VERSION:-unknown} is missing"
# shellcheck disable=SC1090
source "$PATCH_DIR/manifest.env"
[ "${OPENSPEC_VERSION:-}" = "$(basename "$PATCH_DIR")" ] || die 'manifest version does not match the active OpenSpec pin'
[ "${TARGET_PATH:-}" = '.agents/skills/openspec-sync-specs/SKILL.md' ] || die 'manifest target is invalid'
[ "${PATCH_FILE:-}" = 'openspec-sync-specs.patch' ] || die 'manifest patch filename is invalid'
[ -f "$PATCH_DIR/$PATCH_FILE" ] || die 'managed patch file is missing'
[[ "${PATCHED_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || die 'manifest patched hash is invalid'
[ -f "$MANAGED/sync-policy.md" ] || die 'sync policy is missing'
[ -x "$ROOT/scripts/scaffold/reconcile-openspec-skills.sh" ] || die 'repository-local reconciler is missing or not executable'
[ -x "$ROOT/scripts/scaffold/update-openspec.sh" ] || die 'repository-local update wrapper is missing or not executable'

CANONICAL_FILE="$ROOT/$TARGET_PATH"
CANONICAL_DIR="$(dirname "$CANONICAL_FILE")"
[ -f "$CANONICAL_FILE" ] || die 'canonical generated sync skill is missing'
ACTUAL_HASH="$(hash_file "$CANONICAL_FILE")"
[ "$ACTUAL_HASH" = "${PATCHED_SHA256:-}" ] || die "canonical sync skill is pristine, unsupported, or locally modified (sha256 $ACTUAL_HASH)"
GENERATED="$(awk '$1 == "generatedBy:" {gsub(/"/, "", $2); print $2; exit}' "$CANONICAL_FILE")"
[ "$GENERATED" = "$OPENSPEC_VERSION" ] || die "canonical skill version '${GENERATED:-unknown}' does not match the active pin"

CANONICAL_REAL="$(cd "$CANONICAL_DIR" && pwd -P)"
for relative in \
  .claude/skills/openspec-sync-specs \
  .cursor/skills/openspec-sync-specs \
  .codex/skills/openspec-sync-specs \
  .gemini/skills/openspec-sync-specs \
  .opencode/skills/openspec-sync-specs \
  .windsurf/skills/openspec-sync-specs \
  .github/skills/openspec-sync-specs; do
  candidate="$ROOT/$relative"
  if [ -L "$candidate" ]; then
    resolved="$(cd "$candidate" 2>/dev/null && pwd -P || true)"
    [ "$resolved" = "$CANONICAL_REAL" ] || die "$relative is a broken or divergent symlink"
  elif [ -e "$candidate" ]; then
    die "$relative is a duplicate generated skill"
  fi
done

[ -L "$ROOT/.claude/skills/openspec-sync-specs" ] || die 'Claude bridge symlink is missing'
printf '[scaffold-openspec] managed OpenSpec %s sync patch verified\n' "$OPENSPEC_VERSION" >&2
