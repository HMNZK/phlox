#!/usr/bin/env bash
# シミュレーターに PhloxMobile をビルド・インストール・起動する。
#
# 既定はモックデータ付きデモ（-UITesting）。Mac 接続なしで全画面を操作できる。
#
# Usage:
#   ./scripts/run-simulator.sh              # デモ（goldenPath・セッション一覧）
#   ./scripts/run-simulator.sh --live         # 本番 Composition Root（接続設定から）
#   ./scripts/run-simulator.sh --empty      # 空状態シナリオ
#   ./scripts/run-simulator.sh --screen spawn # カンプ④ を直接表示
#   ./scripts/run-simulator.sh --list-screens # 利用可能な --screen 値を表示
#
# Environment:
#   SIMULATOR_NAME  既定 iPhone 16
#   DERIVED_DATA    既定 <repo>/build/DerivedData-run
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="${SCHEME:-PhloxMobile}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 16}"
BUNDLE_ID="com.phlox.mobile.PhloxMobile"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/DerivedData-run}"

MODE="demo"
SCENARIO=""
SCREEN=""

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

list_screens() {
  cat <<'EOF'
利用可能な --screen 値（ios-design.html カンプ対応）:
  connectionSettings   ① 接続設定
  sessionList          ② セッション一覧（既定デモ）
  sessionDetail        ③ セッション詳細・承認
  spawn                ④ 新規タスク
  deleteConfirmation   ⑤ 削除確認
  launchGate           ⑥ 起動ゲート
  chatAnswer           ⑦ 質問への回答
  codexApproval        ⑧ Codex 承認 4 択
  spawnError           ⑨ spawn 失敗
  unreachable          ⑩ 到達不可
  empty                ⑪ 空状態
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) MODE="live"; shift ;;
    --demo) MODE="demo"; shift ;;
    --empty) MODE="demo"; SCENARIO="empty"; shift ;;
    --scenario) MODE="demo"; SCENARIO="$2"; shift 2 ;;
    --screen) MODE="demo"; SCREEN="$2"; shift 2 ;;
    --list-screens) list_screens; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不明な引数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ "$MODE" == "demo" && -z "$SCENARIO" && -z "$SCREEN" ]]; then
  SCENARIO="goldenPath"
fi

resolve_udid() {
  local udid
  udid="$(xcrun simctl list devices available | grep -F "${SIMULATOR_NAME} (" | head -1 | sed -E 's/^[[:space:]]*([^(]+) \(([A-F0-9-]+)\).*/\2/')"
  if [[ -z "$udid" ]]; then
    echo "エラー: シミュレーター '${SIMULATOR_NAME}' が見つかりません。" >&2
    echo "  SIMULATOR_NAME='iPhone 16 Pro' $0" >&2
    xcrun simctl list devices available | grep -E "iPhone|iPad" | head -15 >&2 || true
    exit 1
  fi
  echo "$udid"
}

build_launch_args() {
  LAUNCH_ARGS=()
  if [[ "$MODE" != "demo" ]]; then
    return
  fi
  LAUNCH_ARGS+=(-UITesting -UIViewAnimationsEnabled NO)
  if [[ -n "$SCREEN" ]]; then
    LAUNCH_ARGS+=("-UIScreen=$SCREEN")
  elif [[ -n "$SCENARIO" ]]; then
    LAUNCH_ARGS+=("-UIScenario=$SCENARIO")
  fi
}

echo "=== PhloxMobile シミュレーター起動 ==="
echo "  モード: ${MODE}${SCREEN:+ / 画面=$SCREEN}${SCENARIO:+ / シナリオ=$SCENARIO}"
echo "  端末: ${SIMULATOR_NAME}"

cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "エラー: xcodegen が未インストールです。brew install xcodegen" >&2
  exit 1
fi

if [[ ! -d "$ROOT/../Phlox/Packages/AgentDomain" ]]; then
  echo "警告: 兄弟リポ ../Phlox/Packages/AgentDomain が見つかりません。ビルドが失敗する可能性があります。" >&2
fi

xcodegen generate

UDID="$(resolve_udid)"
echo "  UDID: ${UDID}"

echo "→ ビルド中..."
xcodebuild build \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -quiet

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/PhloxMobile.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "エラー: .app が見つかりません: $APP_PATH" >&2
  exit 1
fi

echo "→ シミュレーター起動..."
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$UDID" -b

echo "→ インストール..."
xcrun simctl install "$UDID" "$APP_PATH"

build_launch_args
echo "→ アプリ起動..."
if [[ ${#LAUNCH_ARGS[@]} -gt 0 ]]; then
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "${LAUNCH_ARGS[@]}"
else
  xcrun simctl launch "$UDID" "$BUNDLE_ID"
fi

echo ""
echo "起動しました。Simulator で操作できます。"
if [[ "$MODE" == "demo" ]]; then
  echo "モックデータモード（-UITesting）。--live で本番フローを試せます。"
fi
