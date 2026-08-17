#!/usr/bin/env bash
# Claude Code PostToolUse adapter. It accepts hook JSON on stdin and formats only the written file.
set -euo pipefail

event="$(cat)"
path="$(printf '%s' "$event" | jq -r '.tool_input.file_path // empty')"
[ -n "$path" ] || exit 0
case "$path" in
  /*) relative="${path#"$PWD"/}" ;;
  *) relative="$path" ;;
esac
[ -f "$relative" ] || exit 0
pnpm format:paths -- "$relative"
