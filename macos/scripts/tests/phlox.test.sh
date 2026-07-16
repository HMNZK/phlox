#!/usr/bin/env bash
#
# scripts/phlox の単体テスト（curl 関数シャドーイング方式。hook-dispatcher.test.sh に倣う）。
# 検証項目:
#   - Authorization/body が curl のコマンドライン引数に現れない（-K -/-d @file 方式）。
#   - 不正 id（kill）・不正 mode（read）・不正 timeout（wait-ready/wait）が拒否される。
#   - 正常値は従来どおり通る。
#   - list/read/wait の出力から制御文字（ANSI エスケープ等）が除去される。
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq が見つかりません"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../phlox
source "$SCRIPT_DIR/../phlox"

export PHLOX_API_URL="http://127.0.0.1:54321"
export PHLOX_TOKEN="test-secret-token-abcdef"
export PHLOX_SESSION_ID="00000000-0000-0000-0000-000000000000"

VALID_UUID="11111111-2222-3333-4444-555555555555"

pass=0
fail=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $label"
        pass=$((pass + 1))
    else
        echo "FAIL: $label (expected=[$expected] actual=[$actual])"
        fail=$((fail + 1))
    fi
}

assert_true() {
    local label="$1" cond="$2"
    if [ "$cond" -eq 0 ]; then
        echo "PASS: $label"
        pass=$((pass + 1))
    else
        echo "FAIL: $label"
        fail=$((fail + 1))
    fi
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    case "$haystack" in
        *"$needle"*)
            echo "PASS: $label"
            pass=$((pass + 1))
            ;;
        *)
            echo "FAIL: $label (haystack=[$haystack] needle=[$needle])"
            fail=$((fail + 1))
            ;;
    esac
}

assert_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    case "$haystack" in
        *"$needle"*)
            echo "FAIL: $label (haystack unexpectedly contains needle=[$needle]) haystack=[$haystack]"
            fail=$((fail + 1))
            ;;
        *)
            echo "PASS: $label"
            pass=$((pass + 1))
            ;;
    esac
}

# --- curl のシャドーイング（実ネットワークアクセスをしない） ---

CURL_CALLED_FILE=$(mktemp)
CURL_ARGS_FILE=$(mktemp)
CURL_STDIN_FILE=$(mktemp)
CURL_BODYFILE_CONTENT_FILE=$(mktemp)

reset_curl_capture() {
    : > "$CURL_CALLED_FILE"
    : > "$CURL_ARGS_FILE"
    : > "$CURL_STDIN_FILE"
    : > "$CURL_BODYFILE_CONTENT_FILE"
}

cleanup() {
    rm -f "$CURL_CALLED_FILE" "$CURL_ARGS_FILE" "$CURL_STDIN_FILE" "$CURL_BODYFILE_CONTENT_FILE"
}
trap cleanup EXIT

mock_status=200
mock_body='{}'

curl() {
    echo "1" >> "$CURL_CALLED_FILE"
    printf '%s\n' "$*" > "$CURL_ARGS_FILE"

    local prev="" out_file="" body_arg="" has_stdin_cfg=0
    for a in "$@"; do
        if [ "$prev" = "-K" ] && [ "$a" = "-" ]; then
            has_stdin_cfg=1
        fi
        if [ "$prev" = "-o" ]; then
            out_file="$a"
        fi
        if [ "$prev" = "-d" ]; then
            body_arg="$a"
        fi
        prev="$a"
    done

    if [ "$has_stdin_cfg" -eq 1 ]; then
        cat > "$CURL_STDIN_FILE"
    fi

    case "$body_arg" in
        @*)
            cat "${body_arg#@}" > "$CURL_BODYFILE_CONTENT_FILE" 2>/dev/null || true
            ;;
    esac

    if [ -n "$out_file" ]; then
        printf '%s' "$mock_body" > "$out_file"
    fi

    printf '%s' "$mock_status"
    return 0
}

# === 1. http_request: Authorization/body が curl 引数に現れない ===

reset_curl_capture
mock_status=200
mock_body='{"ok":true}'
http_request POST "/foo" '{"key":"value"}'

assert_eq "http_request sets HTTP_STATUS" "200" "$HTTP_STATUS"
assert_eq "http_request sets HTTP_BODY" '{"ok":true}' "$HTTP_BODY"

args_line="$(cat "$CURL_ARGS_FILE")"
assert_not_contains "curl args do not contain the token" "$args_line" "$PHLOX_TOKEN"
assert_not_contains "curl args do not contain the raw body" "$args_line" '{"key":"value"}'
assert_contains "curl args use -K - for auth config" "$args_line" "-K -"
assert_contains "curl args use -d @file for body" "$args_line" "-d @"

stdin_content="$(cat "$CURL_STDIN_FILE")"
assert_contains "Authorization sent via -K stdin config" "$stdin_content" "Authorization: Bearer $PHLOX_TOKEN"

bodyfile_content="$(cat "$CURL_BODYFILE_CONTENT_FILE")"
assert_eq "body sent via -d @file matches original body" '{"key":"value"}' "$bodyfile_content"

# GET リクエスト(body 無し)では -d が付かないことも確認
reset_curl_capture
http_request GET "/bar"
args_line="$(cat "$CURL_ARGS_FILE")"
assert_not_contains "GET request without body has no -d flag" "$args_line" "-d "

# === 2. cmd_kill: id の UUID 検証 ===

reset_curl_capture
mock_status=200
mock_body='{}'
output=$(cmd_kill "$VALID_UUID")
assert_eq "cmd_kill with valid UUID succeeds" "removed" "$output"
assert_true "cmd_kill with valid UUID calls curl" "$( [ -s "$CURL_CALLED_FILE" ] && echo 0 || echo 1 )"

reset_curl_capture
rc=0
( cmd_kill "not-a-uuid" ) >/tmp/phlox_test_kill_out.$$ 2>/tmp/phlox_test_kill_err.$$ || rc=$?
assert_true "cmd_kill with invalid id exits non-zero" "$( [ "$rc" -ne 0 ] && echo 0 || echo 1 )"
assert_true "cmd_kill with invalid id does not call curl" "$( [ -s "$CURL_CALLED_FILE" ] && echo 1 || echo 0 )"
rm -f /tmp/phlox_test_kill_out.$$ /tmp/phlox_test_kill_err.$$

# === 3. cmd_read: mode の許可リスト検証 ===

reset_curl_capture
mock_status=200
mock_body='{"text":"hello"}'
output=$(cmd_read --to "$VALID_UUID" --mode screen)
assert_eq "cmd_read with valid mode returns text" "hello" "$output"

reset_curl_capture
rc=0
( cmd_read --to "$VALID_UUID" --mode bogus ) >/tmp/phlox_test_read_out.$$ 2>/tmp/phlox_test_read_err.$$ || rc=$?
assert_true "cmd_read with invalid mode exits non-zero" "$( [ "$rc" -ne 0 ] && echo 0 || echo 1 )"
assert_true "cmd_read with invalid mode does not call curl" "$( [ -s "$CURL_CALLED_FILE" ] && echo 1 || echo 0 )"
rm -f /tmp/phlox_test_read_out.$$ /tmp/phlox_test_read_err.$$

# === 4. cmd_wait_ready / cmd_wait: timeout の数値検証 ===

reset_curl_capture
mock_status=200
mock_body='{"ready":true}'
output=$(cmd_wait_ready --to "$VALID_UUID" --timeout 5)
assert_eq "cmd_wait_ready with valid timeout succeeds" "ready" "$output"

reset_curl_capture
rc=0
( cmd_wait_ready --to "$VALID_UUID" --timeout abc ) >/tmp/phlox_test_wr_out.$$ 2>/tmp/phlox_test_wr_err.$$ || rc=$?
assert_true "cmd_wait_ready with non-numeric timeout exits non-zero" "$( [ "$rc" -ne 0 ] && echo 0 || echo 1 )"
assert_true "cmd_wait_ready with non-numeric timeout does not call curl" "$( [ -s "$CURL_CALLED_FILE" ] && echo 1 || echo 0 )"
rm -f /tmp/phlox_test_wr_out.$$ /tmp/phlox_test_wr_err.$$

reset_curl_capture
rc=0
( cmd_wait_ready --to "$VALID_UUID" --timeout 0 ) >/tmp/phlox_test_wr0_out.$$ 2>/tmp/phlox_test_wr0_err.$$ || rc=$?
assert_true "cmd_wait_ready with zero timeout exits non-zero" "$( [ "$rc" -ne 0 ] && echo 0 || echo 1 )"
rm -f /tmp/phlox_test_wr0_out.$$ /tmp/phlox_test_wr0_err.$$

reset_curl_capture
mock_status=200
mock_body='{"output":"done"}'
output=$(cmd_wait --to "$VALID_UUID" --timeout 30)
assert_eq "cmd_wait with valid timeout succeeds" "done" "$output"

reset_curl_capture
rc=0
( cmd_wait --to "$VALID_UUID" --timeout "not-a-number" ) >/tmp/phlox_test_w_out.$$ 2>/tmp/phlox_test_w_err.$$ || rc=$?
assert_true "cmd_wait with non-numeric timeout exits non-zero" "$( [ "$rc" -ne 0 ] && echo 0 || echo 1 )"
assert_true "cmd_wait with non-numeric timeout does not call curl" "$( [ -s "$CURL_CALLED_FILE" ] && echo 1 || echo 0 )"
rm -f /tmp/phlox_test_w_out.$$ /tmp/phlox_test_w_err.$$

# === 5. 出力サニタイズ: 制御文字(ANSI エスケープ)が除去される ===

raw=$'before\x1b[31mred\x1b[0mafter'
expected='before[31mred[0mafter'
result=$(printf '%s' "$raw" | sanitize_output)
assert_eq "sanitize_output strips ESC bytes" "$expected" "$result"

raw_multiline=$'line1\nline2'
result=$(printf '%s' "$raw_multiline" | sanitize_output)
assert_eq "sanitize_output preserves newlines" "$raw_multiline" "$result"

reset_curl_capture
mock_status=200
mock_body='{"text":"\u001b[31mred\u001b[0m"}'
output=$(cmd_read --to "$VALID_UUID" --mode screen)
assert_eq "cmd_read output has ESC byte stripped" "[31mred[0m" "$output"

reset_curl_capture
mock_status=200
mock_body='{"output":"\u001b[31mdone\u001b[0m"}'
output=$(cmd_wait --to "$VALID_UUID" --timeout 10)
assert_eq "cmd_wait output has ESC byte stripped" "[31mdone[0m" "$output"

reset_curl_capture
mock_status=200
mock_body='{"sessions":[{"id":"11111111-2222-3333-4444-555555555555","name":"a\u001b[1m","kind":"claudeCode","status":"idle","workspace":"/tmp"}]}'
output=$(cmd_list)
assert_not_contains "cmd_list output has no ESC byte" "$output" $'\x1b'

echo ""
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
    exit 1
fi
echo "All tests passed."
