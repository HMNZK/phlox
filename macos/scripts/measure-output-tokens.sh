#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 LOG_FILE..." >&2
  exit 2
fi

command -v uv >/dev/null || { echo "measure-output-tokens: uv が必要です" >&2; exit 2; }

uv run --quiet --with tiktoken==0.11.0 python3 - "${TOKEN_ENCODING:-o200k_base}" "$@" <<'PY'
import pathlib
import sys

import tiktoken

encoding = tiktoken.get_encoding(sys.argv[1])
print("file\tlines\tbytes\ttokens\tencoding")
for name in sys.argv[2:]:
    path = pathlib.Path(name)
    text = path.read_text(errors="replace")
    print(f"{path}\t{text.count(chr(10))}\t{len(text.encode())}\t{len(encoding.encode(text))}\t{encoding.name}")
PY
