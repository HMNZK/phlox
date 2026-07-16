#!/usr/bin/env bash
# lint-raw-values.sh
# Fail (exit 1) if any Swift source under Packages/ or App/ contains raw-value
# color or font literals that should be replaced with design-system tokens.
#
# Detected patterns:
#   Color(red:           — raw UIColor/SwiftUI Color initialiser with numeric components
#   .font(.system(size:  — raw font size instead of design-system type style (DSFont tokens)
#   .font(Font.system(size: — same, explicit Font.system prefix
#   Font.system(size:    — bare Font.system(size:) used as a font value
#
# Usage:
#   ./scripts/lint-raw-values.sh              # scans Packages/ App/ relative to CWD
#   ./scripts/lint-raw-values.sh /some/dir    # scans the given directory (for testing)
set -euo pipefail

SCAN_ROOT="${1:-}"
if [[ -z "$SCAN_ROOT" ]]; then
  # Default: run from repo root, scan Packages/ and App/
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(dirname "$SCRIPT_DIR")"
  TARGETS=("$REPO_ROOT/Packages" "$REPO_ROOT/App")
else
  TARGETS=("$SCAN_ROOT")
fi

FOUND=0

echo "=== lint-raw-values: scanning for raw color/font literals ==="

for target in "${TARGETS[@]}"; do
  if [[ ! -d "$target" ]]; then
    echo "  [skip] $target (not found)"
    continue
  fi

  # .swift ソースのみ対象（.build のバイナリ索引・生成物を誤検出しないため）
  if grep -rn --include='*.swift' --exclude-dir='.build' 'Color(red:' "$target" 2>/dev/null; then
    echo "ERROR: Raw Color(red:...) literal detected. Use design-system tokens instead." >&2
    FOUND=1
  fi

  for font_pattern in '\.font(\.system(size:' '\.font(Font\.system(size:' 'Font\.system(size:'; do
    if grep -rn --include='*.swift' --exclude-dir='.build' "$font_pattern" "$target" 2>/dev/null; then
      echo "ERROR: Raw font size literal detected ($font_pattern). Use DSFont tokens instead." >&2
      FOUND=1
    fi
  done
done

if [[ $FOUND -eq 1 ]]; then
  echo "=== lint-raw-values: FAILED — raw value literals found ===" >&2
  exit 1
fi

echo "=== lint-raw-values: OK — no raw value literals found ==="
exit 0
