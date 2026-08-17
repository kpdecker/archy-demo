#!/usr/bin/env bash
# Lint the Nx projects affected since a comparison base, without writing to the working tree.
#
# Two callers, two ranges:
#   * A contributor or an agent turn-end hook runs it bare. The base is the merge base with the
#     default branch and no head is passed, so Nx treats uncommitted and untracked files as touched
#     — the work that prompted the run has usually not been committed yet.
#   * The pre-push hook runs it with --stdin. Git reports each ref being pushed as
#     "<local ref> <local sha> <remote ref> <remote sha>", which is exactly the range that is about
#     to become shared, so both ends are pinned and unrelated working-tree edits stay out of it.
#
# Using `nx affected` rather than a path-to-project adapter keeps this gate and CI in agreement
# about which projects a change touches.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$WORKSPACE_ROOT"

DEFAULT_BRANCH="${SCAFFOLD_DEFAULT_BRANCH:-main}"
# Git reports a deleted ref or an absent remote branch as the all-zero object id.
EMPTY_SHA_PATTERN='^0{40,}$'

read_stdin=false
[ "${1:-}" = "--stdin" ] && read_stdin=true

is_commit() {
  git rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1
}

# The merge base between a head and the default branch: what a ref the remote has never seen must
# compare against. Taking the head as an argument keeps each pushed ref on its own base.
fallback_base() {
  local head=$1 upstream
  for upstream in "origin/$DEFAULT_BRANCH" "$DEFAULT_BRANCH"; do
    if is_commit "$upstream"; then
      git merge-base "$head" "$upstream" && return 0
    fi
  done
  return 1
}

# Each entry is one "<base>\t<head>" range to check.
ranges=()

if $read_stdin; then
  # `git push --all` and `git push --mirror` send several refs at once. Each gets its own range:
  # collapsing them would let a diagnostic on one ref hide behind another ref's range.
  while read -r _local_ref local_sha _remote_ref remote_sha; do
    [ -n "${local_sha:-}" ] || continue
    # A branch deletion pushes an all-zero local sha and has no source to lint.
    [[ "$local_sha" =~ $EMPTY_SHA_PATTERN ]] && continue

    ref_base=""
    if [[ ! "${remote_sha:-}" =~ $EMPTY_SHA_PATTERN ]] && is_commit "${remote_sha:-}"; then
      ref_base="$remote_sha"
    elif ! ref_base="$(fallback_base "$local_sha")"; then
      printf 'Cannot resolve a lint comparison base for %s; run "pnpm lint".\n' "$local_sha" >&2
      exit 1
    fi
    ranges+=("$ref_base"$'\t'"$local_sha")
  done

  # Nothing to push, or only deletions: there is no range and nothing to lint.
  [ "${#ranges[@]}" -gt 0 ] || exit 0
else
  if ! base="$(fallback_base HEAD)"; then
    printf 'Cannot resolve a lint comparison base; run "pnpm lint" to lint every project.\n' >&2
    exit 1
  fi
  # An empty head is deliberate; see below.
  ranges+=("$base"$'\t')
fi

for range in "${ranges[@]}"; do
  base="${range%%$'\t'*}"
  head="${range#*$'\t'}"
  if [ -n "$head" ]; then
    pnpm exec nx affected --target=lint --base="$base" --head="$head"
  else
    # Omitting --head is deliberate: Nx then counts uncommitted and untracked files as touched,
    # which is what a contributor or an agent that just edited a file needs. The pre-push hook
    # always passes a head, because it must lint the commits being pushed and not unrelated edits.
    pnpm exec nx affected --target=lint --base="$base"
  fi
done
