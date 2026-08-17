#!/usr/bin/env bash
# Provision the native language toolchains implied by canonical language manifests.
#
# Detection reads the manifests directly rather than resolving the Nx project graph: formatting
# dispatches by file extension, so a language needs its toolchain whenever its sources exist,
# whether or not they sit inside a declared Nx project root.
#
# One pass serves both `format:check` and `lint`, because a language's formatter and its linter
# come from the same toolchain: Clippy is a rustup component and `go vet` ships with Go.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/toolchain-versions.env"
: "${GITHUB_PATH:?GITHUB_PATH must be set by GitHub Actions}"

has_manifest() {
  find "$WORKSPACE_ROOT" \
    \( -name node_modules -o -name .git -o -name vendor -o -name target \
       -o -name dist -o -name .venv \) -prune -o \
    -name "$1" -print -quit | grep -q .
}

# A contract project is `app/<name>/contract/contract.json`. Its compatibility gate needs the
# pinned checker, which is neither a language toolchain nor an npm package; a workspace with no
# contract project provisions nothing.
has_contract_project() {
  find "$WORKSPACE_ROOT/app" -mindepth 3 -maxdepth 3 -path '*/contract/contract.json' -print -quit \
    2>/dev/null | grep -q .
}

need_python=false
need_rust=false
need_go=false
need_oasdiff=false
has_manifest pyproject.toml && need_python=true
has_manifest Cargo.toml && need_rust=true
has_manifest go.mod && need_go=true
has_contract_project && need_oasdiff=true

if $need_python; then
  # Ruff formats and lints. uv is what builds, resolves, tests, and typechecks a Python project, and
  # what provisions the interpreter the workspace pins, so installing Ruff alone leaves a Python
  # project formattable but not buildable. Both install into ~/.local/bin, which joins PATH once.
  curl -LsSf "https://astral.sh/ruff/${RUFF_VERSION}/install.sh" | sh
  curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh
  printf '%s\n' "$HOME/.local/bin" >> "$GITHUB_PATH"
  "$HOME/.local/bin/uv" python install "$PYTHON_VERSION"
fi
if $need_rust; then
  rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal --component rustfmt --component clippy
  rustup default "$RUST_TOOLCHAIN"
fi
if $need_go; then
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) go_platform=linux-amd64 ;;
    Linux-aarch64|Linux-arm64) go_platform=linux-arm64 ;;
    *) printf 'Unsupported CI platform for pinned Go: %s-%s\n' "$(uname -s)" "$(uname -m)" >&2; exit 1 ;;
  esac
  go_root="${RUNNER_TEMP:?RUNNER_TEMP must be set by GitHub Actions}/go-${GO_TOOLCHAIN_VERSION}"
  mkdir -p "$go_root"
  curl -LsSf "https://go.dev/dl/go${GO_TOOLCHAIN_VERSION}.${go_platform}.tar.gz" \
    | tar -xz --strip-components=1 -C "$go_root"
  printf '%s/bin\n' "$go_root" >> "$GITHUB_PATH"
fi
if $need_oasdiff; then
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) oasdiff_asset="oasdiff_${OASDIFF_VERSION}_linux_amd64.tar.gz" ;;
    Linux-aarch64|Linux-arm64) oasdiff_asset="oasdiff_${OASDIFF_VERSION}_linux_arm64.tar.gz" ;;
    Darwin-*) oasdiff_asset="oasdiff_${OASDIFF_VERSION}_darwin_all.tar.gz" ;;
    *) printf 'Unsupported CI platform for pinned oasdiff: %s-%s\n' "$(uname -s)" "$(uname -m)" >&2; exit 1 ;;
  esac
  oasdiff_base="https://github.com/oasdiff/oasdiff/releases/download/v${OASDIFF_VERSION}"
  oasdiff_root="${RUNNER_TEMP:?RUNNER_TEMP must be set by GitHub Actions}/oasdiff-${OASDIFF_VERSION}"
  mkdir -p "$oasdiff_root"
  curl -LsSf "$oasdiff_base/$oasdiff_asset" -o "$oasdiff_root/$oasdiff_asset"
  curl -LsSf "$oasdiff_base/checksums.txt" -o "$oasdiff_root/checksums.txt"
  # The release publishes checksums; an asset that does not match one is not installed.
  oasdiff_expected=$(awk -v want="$oasdiff_asset" '$2 == want || $2 == "*" want { print $1 }' \
    "$oasdiff_root/checksums.txt")
  oasdiff_actual=$(shasum -a 256 "$oasdiff_root/$oasdiff_asset" | awk '{ print $1 }')
  if [ -z "$oasdiff_expected" ] || [ "$oasdiff_expected" != "$oasdiff_actual" ]; then
    printf 'oasdiff checksum mismatch for %s (expected %s, got %s)\n' \
      "$oasdiff_asset" "${oasdiff_expected:-<no entry>}" "$oasdiff_actual" >&2
    exit 1
  fi
  tar -xzf "$oasdiff_root/$oasdiff_asset" -C "$oasdiff_root" oasdiff
  printf '%s\n' "$oasdiff_root" >> "$GITHUB_PATH"
fi
