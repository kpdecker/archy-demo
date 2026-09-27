#!/usr/bin/env bash
# scripts/apply-platform-version.sh [--check | --record-current]
#
# Keeps every first-party dependency declaration in this repository -- `@archy-stack/*` on npm,
# `archy-*` on Cargo and PyPI, and every `github.com/kpdecker/archy/packages/*` Go module -- in
# lockstep with the platform version this repository has recorded in .archy/platform.env
# (ARCHY_PLATFORM_VERSION). repo-boot's two tooling packages, @archy-stack/lint-config and
# @archy-stack/package-docs, carry their own recorded versions (ARCHY_LINT_CONFIG_VERSION,
# ARCHY_PACKAGE_DOCS_VERSION) and are never compared against the platform version.
#
# Three modes, run from the repository root:
#
#   (no flag)         Rewrite every manifest to the recorded versions, through each ecosystem's
#                      own structured tool -- `jq` for package.json, `cargo add` for a Cargo
#                      member's direct pin, a format-preserving tomlkit rewrite for the root
#                      workspace's [workspace.dependencies] table, `uv add` for a pyproject.toml,
#                      and `go mod edit -require` for a go.mod -- never a text substitution. Then
#                      reinstalls: `pnpm install`, `cargo update -p <crate>`, `uv lock
#                      --upgrade-package <distribution>`, and `go mod tidy` per module.
#   --check           Read-only: exit 1, naming the manifest and package on stderr, when any
#                      first-party RUNTIME dependency disagrees with the recorded platform
#                      version. Installs nothing, reads text and JSON only (jq), and needs no TOML
#                      library or `uv` -- it runs with neither on PATH.
#   --record-current   Read-only writer: (re)writes .archy/platform.env from the highest version
#                      each of its four keys' manifests already name, reporting any skew found
#                      while doing so, and leaving out a key no manifest names at all.
#
# This file is copied verbatim into every generated repository (repo-boot's platform-updates
# recipe) and is run directly by the repo-upgrade skill and by the seeded Renovate workflow's
# postUpgradeTasks, so it carries no reference to this plugin's own tooling: nothing here sources
# _shared/versions.env, _shared/lib.sh, or any sibling plugin file. Its own third-party tool
# version -- the tomlkit release run with `uv run --no-project --with tomlkit==<version>` to
# rewrite Cargo's [workspace.dependencies] table -- is therefore a literal below, checked against
# TOMLKIT_VERSION by scripts/check-shared-skill-tooling.sh in the Archy repository that ships
# this file.
set -euo pipefail

RECORD=.archy/platform.env
KEYS="ARCHY_PLATFORM_VERSION ARCHY_LINT_CONFIG_VERSION ARCHY_PACKAGE_DOCS_VERSION ARCHY_SCAFFOLD_PLUGIN_VERSION"
readonly TOMLKIT_SPEC='tomlkit==0.13.2'

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; }
die() { printf 'apply-platform-version: %s\n' "$*" >&2; exit 1; }

MODE=rewrite
for arg in "$@"; do
  case "$arg" in
    --check) MODE=check ;;
    --record-current) MODE=record-current ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown arg: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

# --- small helpers ------------------------------------------------------------------------------

# get_var NAME / set_var NAME VALUE — indirect access to one of $KEYS' variables, safe under
# `set -u`: get_var prints "" for a name never assigned this run.
get_var() { eval "printf '%s' \"\${$1:-}\""; }
set_var() { eval "$1=\"\$2\""; }

# commit_file STAGED TARGET — replaces TARGET with STAGED's content, keeping TARGET's mode (or a
# plain redirect's default for a new file) before the rename. Inlined rather than reached from
# _shared/lib.sh's commit_staged_file: this script is copied verbatim into a generated repository
# and cannot reach the plugin's own tree at run time.
commit_file() {
  local staged="$1" target="$2" mode
  if [ -e "$target" ]; then
    mode="$(stat -c '%a' "$target" 2>/dev/null || stat -f '%Lp' "$target")"
  else
    mode="$(printf '%03o' "$(( 0666 & ~0$(umask) ))")"
  fi
  chmod "$mode" "$staged"
  mv "$staged" "$target"
}

# find_manifests NAME — every file named NAME under the repository, outside build and dependency
# output. `find . | while read` (process substitution, never a bare pipe) throughout this script:
# a `grep`/`find` that matches nothing exits non-zero, and piping that into `while read` would
# trip `set -o pipefail` on the ordinary case of "this manifest declares no first-party
# dependency" -- process substitution keeps that failure out of the parent shell's exit status.
find_manifests() {
  find . \
    \( -name node_modules -o -name .git -o -name target -o -name dist -o -name .venv \
       -o -name __pycache__ -o -name vendor -o -name tmp -o -name out-tsc -o -name '*.egg-info' \) \
    -prune -o -type f -name "$1" -print
}

# key_for PACKAGE — the record key PACKAGE's version belongs to, or nothing for a package this
# script does not manage. Every archy-* Cargo/PyPI distribution and every
# github.com/kpdecker/archy/packages/* Go module is a platform-group runtime package
# (packages/README.md's Release groups); repo-boot's two tooling packages, lint-config and
# package-docs, publish to npm only, so only the npm arm needs to name them specially.
key_for() {
  case "$1" in
    @archy-stack/lint-config) printf 'ARCHY_LINT_CONFIG_VERSION' ;;
    @archy-stack/package-docs) printf 'ARCHY_PACKAGE_DOCS_VERSION' ;;
    @archy-stack/*|archy-*|github.com/kpdecker/archy/packages/*) printf 'ARCHY_PLATFORM_VERSION' ;;
    *) return 1 ;;
  esac
}

# highest_version V1 V2 ... — the semver-highest of the given dot-separated version strings,
# compared numerically component by component (never lexically: "0.9.0" must sort below
# "0.10.0"). Node is always present at the workspace root this script runs from.
highest_version() {
  node -e '
    const versions = process.argv.slice(1);
    const parts = (v) => v.split(/[.+-]/).map((p) => (/^\d+$/.test(p) ? Number(p) : p));
    versions.sort((a, b) => {
      const pa = parts(a), pb = parts(b);
      for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        const x = pa[i], y = pb[i];
        if (x === y) continue;
        if (x === undefined) return -1;
        if (y === undefined) return 1;
        if (typeof x === "number" && typeof y === "number") return x - y;
        return String(x) < String(y) ? -1 : 1;
      }
      return 0;
    });
    process.stdout.write(versions[versions.length - 1]);
  ' "$@"
}

# --- .archy/platform.env -------------------------------------------------------------------------

read_record_value() {
  [ -f "$RECORD" ] || return 0
  grep -E "^${1}=" "$RECORD" 2>/dev/null | tail -n1 | cut -d= -f2- || true
}

load_record() {
  local key value
  for key in $KEYS; do
    value="$(read_record_value "$key")"
    set_var "$key" "$value"
  done
}

# write_record — regenerates the whole file from the value currently bound to each of $KEYS, in
# their declared order, leaving out a key with no value. Writers regenerate the whole file rather
# than editing a line in place (design D1).
write_record() {
  mkdir -p "$(dirname "$RECORD")"
  local tmp key value
  tmp="$(mktemp)"
  : > "$tmp"
  for key in $KEYS; do
    value="$(get_var "$key")"
    [ -n "$value" ] || continue
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  done
  commit_file "$tmp" "$RECORD"
}

# --- reading declarations -------------------------------------------------------------------------
# Every *_declarations function prints "<file>\t<package>\t<version>" lines, one per first-party
# dependency it finds. --check and --record-current both read through these; the rewrite mode
# reads them a second time, after editing, to drive the reinstall step.

npm_declarations() {
  local f pkg ver
  while IFS= read -r f; do
    while IFS=$'\t' read -r pkg ver; do
      [ -n "$pkg" ] || continue
      printf '%s\t%s\t%s\n' "$f" "$pkg" "$ver"
    done < <(jq -r '
      ((.dependencies // {}) + (.devDependencies // {}))
      | to_entries[] | select(.key | startswith("@archy-stack/"))
      | "\(.key)\t\(.value)"
    ' "$f" 2>/dev/null)
  done < <(find_manifests package.json)
}

# cargo_workspace_section / cargo_member_section FILE — the raw lines of FILE's root
# [workspace.dependencies] table, or of every [dependencies]/[dev-dependencies]/[build-dependencies]
# table, respectively. Two fixed awk programs rather than one parameterized by a `-v`-supplied
# regex: the BSD awk this repository's own macOS checkouts carry re-escapes a `-v` string before
# using it as a dynamic regex, so a bracket meant literally (`\[workspace\.dependencies\]`) loses
# its backslash and stops matching -- a fixed program has no such string round-trip to lose it in.
cargo_workspace_section() {
  awk '
    /^\[/ { insec = ($0 ~ /^\[workspace\.dependencies\][[:space:]]*$/); next }
    insec { print }
  ' "$1"
}

cargo_member_section() {
  awk '
    /^\[/ { insec = ($0 ~ /^\[(dependencies|dev-dependencies|build-dependencies)\][[:space:]]*$/); next }
    insec { print }
  ' "$1"
}

# cargo_parse_section_lines — reads a table's raw lines on stdin, prints "<package>\t<version>"
# for every archy-* key directly pinned (not delegated to the workspace). A member's
# `archy-name.workspace = true` (dotted-key delegation) and `archy-name = { workspace = true }`
# (the equivalent inline-table spelling) are both skipped: neither declares a version of its own.
cargo_parse_section_lines() {
  local line key val ver
  while IFS= read -r line; do
    case "$line" in archy-*=*) ;; *) continue ;; esac
    key="${line%%=*}"; key="$(printf '%s' "$key" | sed -E 's/[[:space:]]+$//')"
    case "$key" in *.workspace) continue ;; esac
    val="${line#*=}"; val="$(printf '%s' "$val" | sed -E 's/^[[:space:]]+//')"
    case "$val" in *workspace*true*) continue ;; esac
    ver=""
    if [[ "$val" =~ version[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
      ver="${BASH_REMATCH[1]}"
    elif [[ "$val" =~ ^\"([^\"]*)\" ]]; then
      ver="${BASH_REMATCH[1]}"
    fi
    ver="${ver#=}"
    [ -n "$ver" ] || continue
    printf '%s\t%s\n' "$key" "$ver"
  done
}

cargo_workspace_declarations() {
  local file pkg ver
  while IFS= read -r file; do
    while IFS=$'\t' read -r pkg ver; do
      printf '%s\t%s\t%s\n' "$file" "$pkg" "$ver"
    done < <(cargo_workspace_section "$file" | cargo_parse_section_lines)
  done < <(find_manifests Cargo.toml)
}

cargo_member_declarations() {
  local file pkg ver
  while IFS= read -r file; do
    while IFS=$'\t' read -r pkg ver; do
      printf '%s\t%s\t%s\n' "$file" "$pkg" "$ver"
    done < <(cargo_member_section "$file" | cargo_parse_section_lines)
  done < <(find_manifests Cargo.toml)
}

cargo_declarations_all() {
  cargo_workspace_declarations
  cargo_member_declarations
}

python_declarations() {
  local f spec pkg ver
  while IFS= read -r f; do
    while IFS= read -r spec; do
      [ -n "$spec" ] || continue
      pkg="${spec%%==*}"
      ver="${spec#*==}"
      printf '%s\t%s\t%s\n' "$f" "$pkg" "$ver"
    done < <(grep -oE 'archy-[a-zA-Z0-9_-]+(\[[a-zA-Z0-9_,-]+\])?==[0-9][0-9A-Za-z_.+-]*' "$f" 2>/dev/null)
  done < <(find_manifests pyproject.toml)
}

go_declarations() {
  local f spec pkg ver
  while IFS= read -r f; do
    while IFS= read -r spec; do
      [ -n "$spec" ] || continue
      pkg="${spec% v*}"
      ver="${spec##* v}"
      printf '%s\t%s\t%s\n' "$f" "$pkg" "$ver"
    done < <(grep -oE 'github\.com/kpdecker/archy/packages/[a-zA-Z0-9_/-]+ v[0-9][0-9A-Za-z_.+-]*' "$f" 2>/dev/null)
  done < <(find_manifests go.mod)
}

all_declarations() {
  npm_declarations
  cargo_declarations_all
  python_declarations
  go_declarations
}

# --- --check ---------------------------------------------------------------------------------

run_check() {
  load_record
  local platform failed=false file pkg ver key
  platform="$(get_var ARCHY_PLATFORM_VERSION)"
  [ -n "$platform" ] || die "no ARCHY_PLATFORM_VERSION in $RECORD; run --record-current or write the record first"
  while IFS=$'\t' read -r file pkg ver; do
    [ -n "$file" ] || continue
    key="$(key_for "$pkg" || true)"
    [ "$key" = "ARCHY_PLATFORM_VERSION" ] || continue
    if [ "$ver" != "$platform" ]; then
      printf '%s: %s names %s, but the recorded platform version is %s\n' "$file" "$pkg" "$ver" "$platform" >&2
      failed=true
    fi
  done < <(all_declarations)
  if [ "$failed" = true ]; then
    exit 1
  fi
  printf 'every first-party runtime dependency names the recorded platform version (%s)\n' "$platform"
}

# --- --record-current -------------------------------------------------------------------------

run_record_current() {
  local key values ver file pkg chosen count
  for key in $KEYS; do
    values=""
    while IFS=$'\t' read -r file pkg ver; do
      [ -n "$file" ] || continue
      [ "$(key_for "$pkg" || true)" = "$key" ] || continue
      case " $values " in *" $ver "*) ;; *) values="$values $ver" ;; esac
    done < <(all_declarations)
    values="${values# }"
    if [ -z "$values" ]; then
      set_var "$key" ""
      continue
    fi
    # shellcheck disable=SC2086
    chosen="$(highest_version $values)"
    set_var "$key" "$chosen"
    count="$(printf '%s\n' $values | wc -l | tr -d ' ')"
    if [ "$count" -gt 1 ]; then
      printf 'skew found for %s: %s (recording the highest, %s)\n' "$key" "$values" "$chosen" >&2
    fi
  done
  write_record
  printf 'recorded %s from the manifests already on disk\n' "$RECORD"
}

# --- rewrite (default) ------------------------------------------------------------------------

rewrite_npm() {
  local f tmp platform lint_config package_docs
  platform="$(get_var ARCHY_PLATFORM_VERSION)"
  lint_config="$(get_var ARCHY_LINT_CONFIG_VERSION)"
  package_docs="$(get_var ARCHY_PACKAGE_DOCS_VERSION)"
  while IFS= read -r f; do
    tmp="$(mktemp)"
    jq --arg platform "$platform" --arg lint_config "$lint_config" --arg package_docs "$package_docs" '
      def rewrite($field):
        (.[$field] // {}) as $deps
        | if ($deps | length) == 0 then .
          else .[$field] = ($deps | with_entries(
              if (.key == "@archy-stack/lint-config") then
                (if $lint_config != "" then .value = $lint_config else . end)
              elif (.key == "@archy-stack/package-docs") then
                (if $package_docs != "" then .value = $package_docs else . end)
              elif (.key | startswith("@archy-stack/")) then .value = $platform
              else . end
            ))
          end;
      rewrite("dependencies") | rewrite("devDependencies")
    ' "$f" > "$tmp" && commit_file "$tmp" "$f"
  done < <(find_manifests package.json)
}

# rewrite_cargo_workspace — rewrites archy-* entries in every root [workspace.dependencies] table
# through tomlkit, a format-preserving TOML library, touching only a matched entry's `version`
# field (or the whole value, for a bare-string entry) and leaving `registry`/`features`/every
# other key as they are. `cargo add` cannot make this edit: it selects a workspace member, never
# the root's own table (design D2).
rewrite_cargo_workspace() {
  local file platform
  platform="$(get_var ARCHY_PLATFORM_VERSION)"
  while IFS= read -r file; do
    grep -qE '^\[workspace\.dependencies\][[:space:]]*$' "$file" || continue
    [ -n "$(cargo_workspace_section "$file" | cargo_parse_section_lines)" ] || continue
    command -v uv >/dev/null 2>&1 \
      || die "uv is required to rewrite $file's [workspace.dependencies] table (tomlkit runs through it)"
    uv run --no-project --with "$TOMLKIT_SPEC" python3 - "$file" "$platform" <<'PY'
import sys
import tomlkit

path, version = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    document = tomlkit.parse(handle.read())

table = document.get("workspace", {}).get("dependencies")
if table is not None:
    for key in list(table.keys()):
        if not key.startswith("archy-"):
            continue
        entry = table[key]
        pinned = "=" + version
        if hasattr(entry, "keys") and "version" in entry:
            entry["version"] = pinned
        else:
            table[key] = pinned

with open(path, "w", encoding="utf-8") as handle:
    handle.write(tomlkit.dumps(document))
PY
  done < <(find_manifests Cargo.toml)
}

rewrite_cargo_members() {
  local file pkg ver platform
  platform="$(get_var ARCHY_PLATFORM_VERSION)"
  while IFS=$'\t' read -r file pkg ver; do
    [ -n "$file" ] || continue
    [ "$ver" != "$platform" ] || continue
    command -v cargo >/dev/null 2>&1 || die "cargo is required to rewrite $file's $pkg pin"
    ( cd "$(dirname "$file")" && cargo add "$pkg@=$platform" --quiet )
  done < <(cargo_member_declarations)
}

rewrite_python() {
  local file pkg ver platform
  platform="$(get_var ARCHY_PLATFORM_VERSION)"
  while IFS=$'\t' read -r file pkg ver; do
    [ -n "$file" ] || continue
    [ "$ver" != "$platform" ] || continue
    command -v uv >/dev/null 2>&1 || die "uv is required to rewrite $file's $pkg pin"
    ( cd "$(dirname "$file")" && uv add "${pkg}==${platform}" )
  done < <(python_declarations)
}

rewrite_go() {
  local file pkg ver platform
  platform="$(get_var ARCHY_PLATFORM_VERSION)"
  while IFS=$'\t' read -r file pkg ver; do
    [ -n "$file" ] || continue
    [ "$ver" != "$platform" ] || continue
    command -v go >/dev/null 2>&1 || die "go is required to rewrite $file's $pkg pin"
    ( cd "$(dirname "$file")" && go mod edit -require="${pkg}@v${platform}" )
  done < <(go_declarations)
}

reinstall() {
  if command -v pnpm >/dev/null 2>&1 && { [ -f pnpm-workspace.yaml ] || [ -f pnpm-lock.yaml ]; }; then
    pnpm install
  fi

  local lockfile dir pkg
  while IFS= read -r lockfile; do
    command -v cargo >/dev/null 2>&1 || continue
    dir="$(dirname "$lockfile")"
    local cargo_args=()
    while IFS= read -r pkg; do
      [ -n "$pkg" ] || continue
      cargo_args+=(-p "$pkg")
    done < <(cargo_declarations_all | awk -F'\t' -v d="$dir/Cargo.toml" '$1 == d {print $2}' | sort -u)
    [ "${#cargo_args[@]}" -gt 0 ] || continue
    ( cd "$dir" && cargo update "${cargo_args[@]}" )
  done < <(find_manifests Cargo.lock)

  local pyproject
  while IFS= read -r pyproject; do
    command -v uv >/dev/null 2>&1 || continue
    local uv_args=()
    while IFS= read -r pkg; do
      [ -n "$pkg" ] || continue
      uv_args+=(--upgrade-package "$pkg")
    done < <(python_declarations | awk -F'\t' -v f="$pyproject" '$1 == f {print $2}' | sed -E 's/\[[^]]*\]//' | sort -u)
    [ "${#uv_args[@]}" -gt 0 ] || continue
    ( cd "$(dirname "$pyproject")" && uv lock "${uv_args[@]}" )
  done < <(find_manifests pyproject.toml)

  local gomod
  while IFS= read -r gomod; do
    command -v go >/dev/null 2>&1 || continue
    ( cd "$(dirname "$gomod")" && go mod tidy )
  done < <(find_manifests go.mod)
}

run_rewrite() {
  load_record
  [ -n "$(get_var ARCHY_PLATFORM_VERSION)" ] \
    || die "no ARCHY_PLATFORM_VERSION in $RECORD; run --record-current first, or write the record by hand"
  rewrite_npm
  rewrite_cargo_workspace
  rewrite_cargo_members
  rewrite_python
  rewrite_go
  reinstall
  printf 'every first-party manifest now names the recorded platform version\n'
}

case "$MODE" in
  check) run_check ;;
  record-current) run_record_current ;;
  rewrite) run_rewrite ;;
esac
