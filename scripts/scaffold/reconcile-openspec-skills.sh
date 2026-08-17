#!/usr/bin/env bash
# scaffold-managed: openspec-skill-patching
# Reconcile a supported generated OpenSpec sync skill into the canonical .agents home.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${1:-$SCRIPT_DIR/../..}" && pwd)"
MANAGED="$ROOT/.scaffold/openspec"
VERSION_FILE="$MANAGED/version.env"

die() { printf '[scaffold-openspec] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[scaffold-openspec] %s\n' "$*" >&2; }
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die 'sha256sum or shasum is required'
  fi
}
generated_version() {
  awk '$1 == "generatedBy:" {gsub(/"/, "", $2); print $2; exit}' "$1"
}

[ -f "$VERSION_FILE" ] || die "missing $VERSION_FILE; reinstall Scaffold OpenSpec assets"
# shellcheck disable=SC1090
source "$VERSION_FILE"
[[ "${OPENSPEC_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'invalid pinned OpenSpec version'
ACTIVE_VERSION="$OPENSPEC_VERSION"

PATCH_DIR="$MANAGED/patches/$ACTIVE_VERSION"
MANIFEST="$PATCH_DIR/manifest.env"
[ -f "$MANIFEST" ] || die "OpenSpec $ACTIVE_VERSION is unsupported; install its reviewed patch bundle"
# shellcheck disable=SC1090
source "$MANIFEST"

[ "${OPENSPEC_VERSION:-}" = "$ACTIVE_VERSION" ] || die 'manifest version does not match the active OpenSpec pin'
[ "${TARGET_PATH:-}" = '.agents/skills/openspec-sync-specs/SKILL.md' ] || die 'manifest target is invalid'
[ "${PATCH_FILE:-}" = 'openspec-sync-specs.patch' ] || die 'manifest patch filename is invalid'
[[ "${UPSTREAM_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || die 'manifest upstream hash is invalid'
[[ "${PATCHED_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || die 'manifest patched hash is invalid'
[ -f "$PATCH_DIR/$PATCH_FILE" ] || die "missing $PATCH_DIR/$PATCH_FILE"
[ -f "$MANAGED/sync-policy.md" ] || die "missing $MANAGED/sync-policy.md"
command -v git >/dev/null 2>&1 || die 'git is required to apply the managed patch'

CANONICAL_FILE="$ROOT/$TARGET_PATH"
CANONICAL_DIR="$(dirname "$CANONICAL_FILE")"
CLAUDE_DIR="$ROOT/.claude/skills/openspec-sync-specs"
SOURCE_DIR="$CANONICAL_DIR"
if [ -e "$CLAUDE_DIR" ] && [ ! -L "$CLAUDE_DIR" ]; then
  SOURCE_DIR="$CLAUDE_DIR"
  log 'using refreshed .claude sync skill as the upgrade candidate'
fi
[ -f "$SOURCE_DIR/SKILL.md" ] || die 'generated openspec-sync-specs skill is missing; run the controlled OpenSpec update, then reconcile'

STAGE="$(mktemp -d "$MANAGED/.reconcile.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT
STAGED_DIR="$STAGE/.agents/skills/openspec-sync-specs"
mkdir -p "$(dirname "$STAGED_DIR")"
cp -R "$SOURCE_DIR" "$STAGED_DIR"
STAGED_FILE="$STAGED_DIR/SKILL.md"

GENERATED="$(generated_version "$STAGED_FILE")"
[ "$GENERATED" = "$ACTIVE_VERSION" ] || die "generated skill version '${GENERATED:-unknown}' is unsupported; expected $ACTIVE_VERSION"

CURRENT_HASH="$(hash_file "$STAGED_FILE")"
case "$CURRENT_HASH" in
  "$PATCHED_SHA256")
    log "OpenSpec $ACTIVE_VERSION sync skill is already patched"
    ;;
  "$UPSTREAM_SHA256")
    (
      cd "$STAGE"
      GIT_CEILING_DIRECTORIES="$ROOT" git apply "$PATCH_DIR/$PATCH_FILE"
    ) || die 'reviewed patch did not apply to the pristine generated skill'
    ;;
  *)
    die "generated sync skill is unsupported or locally modified (sha256 $CURRENT_HASH); canonical skill was not replaced"
    ;;
esac

FINAL_HASH="$(hash_file "$STAGED_FILE")"
[ "$FINAL_HASH" = "$PATCHED_SHA256" ] || die "patched hash mismatch: expected $PATCHED_SHA256, got $FINAL_HASH"

if [ "$SOURCE_DIR" = "$CANONICAL_DIR" ] && [ "$CURRENT_HASH" = "$PATCHED_SHA256" ] \
   && [ -L "$CLAUDE_DIR" ]; then
  CANONICAL_REAL="$(cd "$CANONICAL_DIR" && pwd -P)"
  CLAUDE_REAL="$(cd "$CLAUDE_DIR" 2>/dev/null && pwd -P || true)"
  if [ "$CLAUDE_REAL" = "$CANONICAL_REAL" ]; then
    log "managed OpenSpec $ACTIVE_VERSION sync patch is already reconciled ($FINAL_HASH)"
    exit 0
  fi
fi

mkdir -p "$(dirname "$CANONICAL_DIR")" "$ROOT/.claude/skills"
PREVIOUS_CANONICAL="$STAGE/previous-canonical"
PREVIOUS_CLAUDE="$STAGE/previous-claude"
if [ -e "$CANONICAL_DIR" ] || [ -L "$CANONICAL_DIR" ]; then
  mv "$CANONICAL_DIR" "$PREVIOUS_CANONICAL"
fi
if ! mv "$STAGED_DIR" "$CANONICAL_DIR"; then
  [ ! -e "$PREVIOUS_CANONICAL" ] || mv "$PREVIOUS_CANONICAL" "$CANONICAL_DIR"
  die 'could not install the patched canonical skill'
fi

if [ -e "$CLAUDE_DIR" ] || [ -L "$CLAUDE_DIR" ]; then
  mv "$CLAUDE_DIR" "$PREVIOUS_CLAUDE"
fi
if ! ln -s '../../.agents/skills/openspec-sync-specs' "$CLAUDE_DIR"; then
  mv "$CANONICAL_DIR" "$STAGED_DIR"
  [ ! -e "$PREVIOUS_CANONICAL" ] || mv "$PREVIOUS_CANONICAL" "$CANONICAL_DIR"
  [ ! -e "$PREVIOUS_CLAUDE" ] || mv "$PREVIOUS_CLAUDE" "$CLAUDE_DIR"
  die 'could not restore the Claude skill symlink'
fi

log "installed managed OpenSpec $ACTIVE_VERSION sync patch ($FINAL_HASH)"
