#!/bin/sh
# Debug ビルドして既存の Phlox を終了し、Debug 版を起動し直す(1コマンド)。
#
#   scripts/debug-build-restart.sh
#
# - ビルドは同期実行し、失敗したら再起動せずに終了する
# - 終了→起動は nohup でデタッチする。Phlox 内のターミナル(セッション)から
#   実行してもアプリ終了に巻き込まれず再起動が完走する
# - 既存インスタンスを必ず終了してから起動する(二重起動すると hook/control
#   ポート 57398/57399 が競合する。CLAUDE.md 参照)
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
DERIVED_DATA=/tmp/PhloxBuild
APP_PATH="$DERIVED_DATA/Build/Products/Debug/Phlox.app"

xcodebuild -project "$REPO_ROOT/Phlox.xcodeproj" -scheme Phlox \
  -configuration Debug -derivedDataPath "$DERIVED_DATA" build

# ログ出力先は mktemp で都度生成する(固定 /tmp パスの予測可能性/衝突を避ける。CWE-377)。
LOG_FILE=$(mktemp -t phlox-restart)

PHLOX_APP_PATH="$APP_PATH" nohup sh -c '
  sleep 3
  osascript -e "quit app \"Phlox\"" 2>/dev/null
  for _ in $(seq 1 30); do
    pgrep -x Phlox >/dev/null || break
    sleep 1
  done
  pgrep -x Phlox >/dev/null && pkill -x Phlox
  sleep 2
  open "$PHLOX_APP_PATH"
' >"$LOG_FILE" 2>&1 &

echo "ビルド成功。3秒後に Phlox を再起動します(ログ: $LOG_FILE)"
