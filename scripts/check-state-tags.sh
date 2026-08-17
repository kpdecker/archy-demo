#!/usr/bin/env bash
# Verify that every state tag records the provenance a replay fixture needs.
#
# A state tag names a reviewed state of this repository. Its annotation carries the plugin source
# that produced the state, so an evaluation cloning the tag can tell what built the tree and whether
# that source can be reconstructed. This check reads only the local object database, so it passes in
# a throwaway clone with no network access.
set -euo pipefail

REQUIRED_TRAILERS=(Plugin-Version Source-Commit Source-Dirty)

status=0
found=0

trailer_value() {
  local message=$1 key=$2
  printf '%s\n' "$message" | awk -v key="$key:" '
    $1 == key { $1 = ""; sub(/^[[:space:]]+/, ""); print; exit }
  '
}

while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  found=$((found + 1))
  tag=${ref#refs/tags/}
  tag_ok=1

  if [ "$(git cat-file -t "$ref")" != "tag" ]; then
    printf 'FAIL %s: lightweight tag; state tags must be annotated\n' "$tag" >&2
    status=1
    continue
  fi

  message=$(git for-each-ref --format='%(contents)' "$ref")
  for trailer in "${REQUIRED_TRAILERS[@]}"; do
    if [ -z "$(trailer_value "$message" "$trailer")" ]; then
      printf 'FAIL %s: missing or empty %s trailer\n' "$tag" "$trailer" >&2
      status=1
      tag_ok=0
    fi
  done

  if [ "$tag_ok" -eq 1 ]; then
    printf 'ok   %s (%s)\n' "$tag" "$(trailer_value "$message" Source-Commit)"
  fi
done < <(git for-each-ref --format='%(refname)' 'refs/tags/state/*')

if [ "$found" -eq 0 ]; then
  printf 'FAIL no state/* tags found; fetch tags (actions/checkout needs fetch-depth: 0)\n' >&2
  exit 1
fi

printf '%d state tag(s) checked\n' "$found"
exit "$status"
