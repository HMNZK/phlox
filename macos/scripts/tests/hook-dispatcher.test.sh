#!/usr/bin/env bash
#
# hook-dispatcher.sh の基本ルーティング単体テスト。
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq が見つかりません"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hook-dispatcher.sh
source "$SCRIPT_DIR/../hook-dispatcher.sh"

export PHLOX_SESSION_ID="test-session-uuid"
export CLAUDE_HOOKS_URL="http://127.0.0.1:54321/hook"
export PHLOX_ORCHESTRATION_GUIDE=""
# セッション env から漏れる PHLOX_TOKEN を除去し、各テストが明示的に制御できるようにする
# （未設定なら平文 curl 経路、設定時のみ認証経路を検証する）。
unset PHLOX_TOKEN

pass=0
fail=0

# 捕捉はファイル経由で行う。curl を `printf ... | curl -K -` のようにパイプ右辺で呼ぶと
# curl 関数はサブシェルで走り、グローバル変数への代入が親シェルへ伝播しないため。
CAP_DIR="$(mktemp -d)"
trap 'rm -rf "$CAP_DIR"' EXIT

curl() {
    : > "$CAP_DIR/body"; : > "$CAP_DIR/url"; : > "$CAP_DIR/stdin"
    printf '%s' "$*" > "$CAP_DIR/args"
    local read_config=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -d) shift; printf '%s' "${1:-}" > "$CAP_DIR/body" ;;
            -K) shift; [ "${1:-}" = "-" ] && read_config=1 ;;
            http://*) printf '%s' "$1" > "$CAP_DIR/url" ;;
        esac
        shift || true
    done
    # -K - のとき、Authorization ヘッダ等の config は stdin から渡る（argv=ps 露出を避けるため）。
    if [ "$read_config" -eq 1 ]; then
        cat > "$CAP_DIR/stdin"
    fi
    return 0
}

captured_body() { cat "$CAP_DIR/body" 2>/dev/null || true; }
captured_url()  { cat "$CAP_DIR/url" 2>/dev/null || true; }
captured_stdin(){ cat "$CAP_DIR/stdin" 2>/dev/null || true; }
captured_args() { cat "$CAP_DIR/args" 2>/dev/null || true; }

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $label"
        pass=$((pass + 1))
    else
        echo "FAIL: $label (expected=$expected actual=$actual)"
        fail=$((fail + 1))
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        echo "PASS: $label"
        pass=$((pass + 1))
    else
        echo "FAIL: $label (missing '$needle' in: $haystack)"
        fail=$((fail + 1))
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        echo "FAIL: $label (unexpected '$needle' found)"
        fail=$((fail + 1))
    else
        echo "PASS: $label"
        pass=$((pass + 1))
    fi
}

run_hook() {
    local kind="$1" payload="$2"
    : > "$CAP_DIR/body"; : > "$CAP_DIR/url"; : > "$CAP_DIR/stdin"; : > "$CAP_DIR/args"
    hook_dispatcher_main "$kind" <<< "$payload"
}

json_field() {
    printf '%s' "$(captured_body)" | jq -r "$1"
}

run_hook "stop" '{"exit_code":7,"turn_id":"turn-1","session_id":"native-1"}'
assert_eq "stop posts to hook URL" "$CLAUDE_HOOKS_URL" "$(captured_url)"
assert_eq "stop kind" "stop" "$(json_field '.kind')"
assert_eq "stop exitCode" "7" "$(json_field '.exitCode')"
assert_eq "stop turnId" "turn-1" "$(json_field '.turnId')"
assert_eq "stop native id" "native-1" "$(json_field '.nativeSessionId')"

run_hook "preToolUse" '{"tool_name":"Shell"}'
assert_eq "preToolUse kind" "preToolUse" "$(json_field '.kind')"
assert_eq "preToolUse tool" "Shell" "$(json_field '.toolName')"

run_hook "postToolUse" '{"toolName":"Edit","tool_response":{"exit_code":0}}'
assert_eq "postToolUse kind" "postToolUse" "$(json_field '.kind')"
assert_eq "postToolUse tool" "Edit" "$(json_field '.toolName')"

run_hook "userPromptSubmit" '{"generation_id":"gen-1"}'
assert_eq "userPromptSubmit kind" "userPromptSubmit" "$(json_field '.kind')"
assert_eq "userPromptSubmit turnId" "gen-1" "$(json_field '.turnId')"

export PHLOX_ORCHESTRATION_GUIDE="guide text"
output="$(run_hook "userPromptSubmit" '{}')"
assert_eq "userPromptSubmit emits no additional context when guide env is set" "" "$output"
export PHLOX_ORCHESTRATION_GUIDE=""

# --- 認証（A1 回帰）: PHLOX_TOKEN があれば Authorization を -K -（stdin config）で付与する ---
export PHLOX_TOKEN="secret-token-xyz"
run_hook "sessionStart" '{}'
assert_eq "auth: still posts to hook URL with token" "$CLAUDE_HOOKS_URL" "$(captured_url)"
assert_contains "auth: Authorization Bearer sent via stdin config" "Authorization: Bearer secret-token-xyz" "$(captured_stdin)"
assert_not_contains "auth: token NOT in curl argv (no ps exposure)" "secret-token-xyz" "$(captured_args)"
unset PHLOX_TOKEN

# --- EXIT_CODE 非数値でも set -e で死なず stop 通知を出す（回帰）---
# jq が非数値文字列を返しても --argjson でパースエラーにならず、POST が実行されること。
run_hook "stop" '{"exit_code":"abc"}'
assert_eq "stop with non-numeric exit_code still posts" "$CLAUDE_HOOKS_URL" "$(captured_url)"
assert_eq "stop non-numeric exit_code falls back to 0" "0" "$(json_field '.exitCode')"

# --- 接続拒否の再試行（ADR 0233）: 終了コード7だけを再試行し、タイムアウト・HTTPエラーは再試行しない ---
# 呼び出し回数と、呼び出しごとの終了コード（先頭から消費。尽きたら0）をファイルで持つ（curl はパイプ右辺で呼ばれ得るため）。
RC_FILE="$CAP_DIR/rc"
CALLS_FILE="$CAP_DIR/calls"
export PHLOX_CONNECT_RETRY_INTERVAL=0
export PHLOX_CONNECT_RETRY_ATTEMPTS=4

curl() {
    echo 1 >> "$CALLS_FILE"
    local rc=0
    if [ -s "$RC_FILE" ]; then
        rc="$(head -n 1 "$RC_FILE")"
        tail -n +2 "$RC_FILE" > "$RC_FILE.next"; mv "$RC_FILE.next" "$RC_FILE"
    fi
    # -K - の設定は読み捨てる（パイプの書き手が SIGPIPE にならないように）。
    case " $* " in *" -K "*) cat > /dev/null ;; esac
    return "$rc"
}

curl_calls() { wc -l < "$CALLS_FILE" | tr -d ' '; }

run_with_rcs() {
    : > "$CALLS_FILE"; printf '%s' "$1" > "$RC_FILE"
    run_hook "sessionStart" '{}'
}

run_with_rcs $'7\n7\n'
assert_eq "refused twice then success: 3 calls" "3" "$(curl_calls)"

run_with_rcs $'7\n7\n7\n7\n7\n'
assert_eq "always refused: stops at the attempt limit (4)" "4" "$(curl_calls)"

run_with_rcs $'28\n'
assert_eq "timeout (28) is NOT retried" "1" "$(curl_calls)"

run_with_rcs $'22\n'
assert_eq "HTTP error (22) is NOT retried" "1" "$(curl_calls)"

export PHLOX_TOKEN="secret-token-xyz"
run_with_rcs $'7\n'
assert_eq "authenticated post is retried on refusal" "2" "$(curl_calls)"
unset PHLOX_TOKEN

echo ""
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
    exit 1
fi
echo "All tests passed."
