#!/usr/bin/env bash
# Format supplied, staged, or all workspace paths by dispatching each one to its language's
# formatter from a single extension table.
#
# No Nx project graph is consulted. Formatting is file-scoped and carries no dependency semantics,
# so the owning project supplies nothing that the file's own path and its nearest canonical language
# manifest do not -- gofmt takes no configuration, Prettier and Ruff discover theirs hierarchically,
# and the one setting that is genuinely per-project (the Rust edition) is read from the nearest
# Cargo.toml below. Each formatter is invoked once per run rather than once per path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$WORKSPACE_ROOT"

UV_VERSION="" RUFF_VERSION="" RUST_TOOLCHAIN="" GO_TOOLCHAIN_VERSION=""
if [ -f "$WORKSPACE_ROOT/scripts/toolchain-versions.env" ]; then
  # shellcheck disable=SC1091
  . "$WORKSPACE_ROOT/scripts/toolchain-versions.env"
fi

mode=write
source=explicit
staged=false
end_of_options=false
while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    --staged) staged=true; source=staged; shift ;;
    --all) source=all; shift ;;
    --check) mode=check; shift ;;
    --) end_of_options=true; shift; break ;;
    -*) printf 'format-paths: unknown option %s\n' "$1" >&2; exit 2 ;;
    *) break ;;
  esac
done

# Option parsing stops at the first path, so a flag written after one is collected as a path and
# then dropped by the is-a-file test below -- which would silently invert `--check` into a write.
# Reject it with the same error a leading bad flag gets. Only `--` suppresses the check, so a file
# genuinely named `--check` stays addressable.
if ! $end_of_options; then
  for argument in "$@"; do
    case "$argument" in
      -*)
        printf 'format-paths: unknown option %s\n' "$argument" >&2
        printf '  options must precede paths; pass -- before a path that begins with a dash.\n' >&2
        exit 2
        ;;
    esac
  done
fi

paths=()
case "$source" in
  staged)
    while IFS= read -r -d '' file; do paths+=("$file"); done \
      < <(git diff --cached --name-only --diff-filter=ACMR -z)
    ;;
  all)
    # Tracked plus untracked-but-not-ignored, so a newly written file formats before it is added
    # while everything .gitignore excludes stays out.
    while IFS= read -r -d '' file; do paths+=("$file"); done \
      < <(git ls-files -z --cached --others --exclude-standard)
    ;;
  *) paths=("$@") ;;
esac
[ "${#paths[@]}" -gt 0 ] || exit 0

# Vendored and generated trees belong to no formatter. Prettier already honors .prettierignore, so
# this list exists for the native formatters, which share no ignore file of their own.
native_excluded() {
  case "/$1" in
    */node_modules/*|*/vendor/*|*/target/*|*/dist/*|*/.venv/*|*/.ruff_cache/*|*/.nx/*) return 0 ;;
  esac
  return 1
}

# Walk up for the nearest Cargo.toml that declares a literal edition. A crate that inherits with
# `edition.workspace = true` writes no quoted value, so the walk continues to the workspace manifest
# that defines it.
rust_edition_for() {
  local dir="$1" edition
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -f "$dir/Cargo.toml" ]; then
      edition="$(awk -F '"' \
        '/^[[:space:]]*edition[[:space:]]*=[[:space:]]*"/ { print $2; exit }' "$dir/Cargo.toml")"
      if [ -n "$edition" ]; then printf '%s\n' "$edition"; return 0; fi
    fi
    [ "$dir" = "$WORKSPACE_ROOT" ] && break
    dir="$(dirname "$dir")"
  done
  printf '2021\n'
}

require_tool() {
  local tool="$1" language="$2" pin="$3" example="$4"
  command -v "$tool" >/dev/null 2>&1 && return 0
  {
    printf 'format-paths: cannot format %s -- `%s` is not on PATH.\n' "$language" "$tool"
    printf '  first affected path: %s\n' "$example"
    printf '  pinned version:      %s\n' "${pin:-unpinned}"
    printf '  provision it with scripts/setup-formatters-ci.sh, or install it locally.\n'
  } >&2
  exit 1
}

# Resolve a Ruff matching the workspace pin, and set RUFF_CMD to its argv prefix.
#
# A globally installed `ruff` is used only when its version matches the pin, so an unrelated
# install cannot silently format the repository to a different style. Otherwise uv runs the pinned
# release: that is the path a generated Python repository takes, where `uv` is a documented
# prerequisite but the service's Ruff lives inside its own uv environment rather than on PATH.
RUFF_CMD=()
resolve_ruff() {
  local example="$1" installed=""
  if command -v ruff >/dev/null 2>&1; then
    installed="$(ruff --version 2>/dev/null | awk '{ print $2 }')"
    if [ -z "$RUFF_VERSION" ] || [ "$installed" = "$RUFF_VERSION" ]; then
      RUFF_CMD=(ruff)
      return 0
    fi
  fi
  if [ -n "$RUFF_VERSION" ] && command -v uv >/dev/null 2>&1; then
    RUFF_CMD=(uv tool run "ruff@$RUFF_VERSION")
    return 0
  fi
  {
    printf 'format-paths: cannot format Python at the pinned Ruff version.\n'
    printf '  first affected path: %s\n' "$example"
    printf '  pinned version:      %s\n' "${RUFF_VERSION:-unpinned}"
    if [ -n "$installed" ]; then
      printf '  `ruff` on PATH is %s, which does not match the pin.\n' "$installed"
    else
      printf '  no `ruff` on PATH, and no `uv` to run the pinned release.\n'
    fi
    printf '  provision it with scripts/setup-formatters-ci.sh, or install uv.\n'
  } >&2
  exit 1
}

prettier_paths=() ruff_paths=() go_paths=() rust_paths=() rust_editions=()
absolutes=() relatives=() befores=()

for supplied in "${paths[@]}"; do
  case "$supplied" in
    /*) absolute="$supplied" ;;
    *) absolute="$WORKSPACE_ROOT/$supplied" ;;
  esac
  [ -f "$absolute" ] || continue
  absolute="$(cd "$(dirname "$absolute")" && pwd -P)/$(basename "$absolute")"
  case "$absolute" in
    "$WORKSPACE_ROOT"/*) relative="${absolute#"$WORKSPACE_ROOT"/}" ;;
    *) printf 'Formatting path is outside the workspace: %s\n' "$supplied" >&2; exit 1 ;;
  esac

  case "$relative" in
    *.go)
      native_excluded "$relative" && continue
      go_paths+=("$relative")
      ;;
    *.rs)
      native_excluded "$relative" && continue
      rust_paths+=("$relative")
      rust_editions+=("$(rust_edition_for "$(dirname "$absolute")")")
      ;;
    *.py|*.pyi)
      native_excluded "$relative" && continue
      ruff_paths+=("$relative")
      ;;
    *)
      # Prettier decides for itself what it can parse, via --ignore-unknown.
      prettier_paths+=("$relative")
      ;;
  esac

  absolutes+=("$absolute")
  relatives+=("$relative")
  if $staged; then befores+=("$(shasum -a 256 "$absolute" | awk '{print $1}')"); fi
done
[ "${#absolutes[@]}" -gt 0 ] || exit 0

if [ "${#go_paths[@]}" -gt 0 ]; then
  require_tool gofmt Go "$GO_TOOLCHAIN_VERSION" "${go_paths[0]}"
  if [ "$mode" = check ]; then
    unformatted="$(gofmt -l -- "${go_paths[@]}")"
    if [ -n "$unformatted" ]; then
      printf 'Go files need formatting:\n%s\n' "$unformatted" >&2
      exit 1
    fi
  else
    gofmt -w -- "${go_paths[@]}"
  fi
fi

if [ "${#rust_paths[@]}" -gt 0 ]; then
  require_tool rustfmt Rust "$RUST_TOOLCHAIN" "${rust_paths[0]}"
  # rustfmt takes one --edition per invocation, so paths group by edition. A workspace on a single
  # edition -- the usual case -- still resolves to exactly one invocation.
  editions="$(printf '%s\n' "${rust_editions[@]}" | sort -u)"
  while IFS= read -r edition; do
    [ -n "$edition" ] || continue
    batch=()
    index=0
    while [ "$index" -lt "${#rust_paths[@]}" ]; do
      if [ "${rust_editions[$index]}" = "$edition" ]; then batch+=("${rust_paths[$index]}"); fi
      index=$((index + 1))
    done
    if [ "$mode" = check ]; then
      rustfmt --edition "$edition" --check -- "${batch[@]}"
    else
      rustfmt --edition "$edition" -- "${batch[@]}"
    fi
  done <<EOF
$editions
EOF
fi

if [ "${#ruff_paths[@]}" -gt 0 ]; then
  resolve_ruff "${ruff_paths[0]}"
  if [ "$mode" = check ]; then
    "${RUFF_CMD[@]}" format --check -- "${ruff_paths[@]}"
  else
    "${RUFF_CMD[@]}" format -- "${ruff_paths[@]}"
  fi
fi

if [ "${#prettier_paths[@]}" -gt 0 ]; then
  if [ "$mode" = check ]; then
    pnpm exec prettier --check --ignore-unknown -- "${prettier_paths[@]}"
  else
    pnpm exec prettier --write --ignore-unknown -- "${prettier_paths[@]}"
  fi
fi

if $staged; then
  index=0
  while [ "$index" -lt "${#absolutes[@]}" ]; do
    after="$(shasum -a 256 "${absolutes[$index]}" | awk '{print $1}')"
    if [ "${befores[$index]}" != "$after" ]; then git add -- "${relatives[$index]}"; fi
    index=$((index + 1))
  done
fi
