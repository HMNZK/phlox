#!/usr/bin/env bash
# 任意のコマンドを実行し、成功時だけ出力を圧縮する。
set -uo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 LABEL COMMAND [ARG...]" >&2
  exit 2
fi

label="$1"
shift
output_mode="${COMPACT_COMMAND_OUTPUT-compact}"

case "$output_mode" in
  compact|full) ;;
  *) echo "compact-command: COMPACT_COMMAND_OUTPUT は compact または full を指定: $output_mode" >&2; exit 2 ;;
esac

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

"$@" >"$log" 2>&1
command_exit=$?
if [ "$command_exit" -ne 0 ]; then
  cat "$log"
  exit "$command_exit"
fi

if [ "$output_mode" = "full" ]; then
  cat "$log"
elif [ -n "${COMPACT_COMMAND_SUMMARY_PATTERN-}" ]; then
  summary="$(grep -E "$COMPACT_COMMAND_SUMMARY_PATTERN" "$log" | tail -1)"
  if [ -n "$summary" ]; then
    printf '%s\n' "$summary"
  else
    tail -40 "$log"
  fi
else
  echo "$label: OK（要約未対応）"
fi
