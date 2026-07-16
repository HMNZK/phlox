#!/bin/bash
# Phlox hook dispatcher.
#
# Claude Code から各種フック発火時に呼ばれる。引数 $1 でフック種別を受け取り、
# stdin の JSON ペイロードから必要なフィールドを抽出して、
# $CLAUDE_HOOKS_URL に POST する。
#
# 必須環境変数:
#   PHLOX_SESSION_ID  ダッシュボードが発行した SessionID (UUID)
#   CLAUDE_HOOKS_URL  投稿先 URL (例: http://127.0.0.1:54321/hook)
#
# どちらかが未設定なら何もせず終了 (= ダッシュボード外で起動された Claude Code)。

set -e

# --- main ---

hook_dispatcher_main() {
    local KIND="${1:-}"

    if [ -z "$PHLOX_SESSION_ID" ] || [ -z "$CLAUDE_HOOKS_URL" ] || [ -z "$KIND" ]; then
        exit 0
    fi

    local PAYLOAD TOOL BODY NATIVE_SID
    PAYLOAD=$(cat)
    NATIVE_SID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // ""' 2>/dev/null || echo "")

    case "$KIND" in
        sessionStart)
            BODY=$(jq -nc \
                --arg sid "$PHLOX_SESSION_ID" \
                '{sessionId: $sid, kind: "sessionStart"}')
            ;;
        notification)
            MESSAGE=$(printf '%s' "$PAYLOAD" | jq -r '.message // ""')
            BODY=$(jq -nc \
                --arg sid "$PHLOX_SESSION_ID" \
                --arg msg "$MESSAGE" \
                '{sessionId: $sid, kind: "notification", message: $msg}')
            ;;
        stop)
            EXIT_CODE=$(printf '%s' "$PAYLOAD" | jq -r '.exit_code // .exitCode // .tool_response.exit_code // .tool_response.exitCode // 0' 2>/dev/null || echo 0)
            # jq が数値でない文字列（例 "abc"）を返すと後続の --argjson code がパースエラーになり、
            # set -e で stop 通知の POST 自体が飛ばずスクリプトが死ぬ。数値でなければ 0 にフォールバックする。
            if ! [[ "$EXIT_CODE" =~ ^-?[0-9]+$ ]]; then
                EXIT_CODE=0
            fi
            TURN_ID=$(printf '%s' "$PAYLOAD" | jq -r '.turn_id // .generation_id // ""')
            if [ -n "$TURN_ID" ]; then
                BODY=$(jq -nc \
                    --arg sid "$PHLOX_SESSION_ID" \
                    --argjson code "$EXIT_CODE" \
                    --arg turnId "$TURN_ID" \
                    '{sessionId: $sid, kind: "stop", exitCode: $code, turnId: $turnId}')
            else
                BODY=$(jq -nc \
                    --arg sid "$PHLOX_SESSION_ID" \
                    --argjson code "$EXIT_CODE" \
                    '{sessionId: $sid, kind: "stop", exitCode: $code}')
            fi
            ;;
        preToolUse)
            TOOL=$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // .toolName // "Shell"')
            BODY=$(jq -nc \
                --arg sid "$PHLOX_SESSION_ID" \
                --arg tool "$TOOL" \
                '{sessionId: $sid, kind: "preToolUse", toolName: $tool}')
            ;;
        postToolUse)
            TOOL=$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // .toolName // "Shell"' 2>/dev/null || echo "Shell")
            EXIT_CODE=$(printf '%s' "$PAYLOAD" | jq -r '.tool_response.exit_code // .tool_response.exitCode // 0' 2>/dev/null || echo 0)
            BODY=$(jq -nc \
                --arg sid "$PHLOX_SESSION_ID" \
                --arg tool "$TOOL" \
                '{sessionId: $sid, kind: "postToolUse", toolName: $tool}')
            ;;
        userPromptSubmit)
            TURN_ID=$(printf '%s' "$PAYLOAD" | jq -r '.turn_id // .generation_id // ""')
            if [ -n "$TURN_ID" ]; then
                BODY=$(jq -nc \
                    --arg sid "$PHLOX_SESSION_ID" \
                    --arg turnId "$TURN_ID" \
                    '{sessionId: $sid, kind: "userPromptSubmit", turnId: $turnId}')
            else
                BODY=$(jq -nc \
                    --arg sid "$PHLOX_SESSION_ID" \
                    '{sessionId: $sid, kind: "userPromptSubmit"}')
            fi
            ;;
        *)
            exit 0
            ;;
    esac

    if [ -n "$NATIVE_SID" ]; then
        BODY=$(printf '%s' "$BODY" | jq -c --arg nativeSessionId "$NATIVE_SID" '. + {nativeSessionId: $nativeSessionId}')
    fi

    # --max-time: HookServer が万一応答しなくても curl を無限待ちさせない（イベントは応答前に配送済み）。
    # 認証: PHLOX_TOKEN があれば Authorization: Bearer を付与する（無認証 hook POST による偽 stop/idle
    # 注入対策・CWE-306）。トークンは curl の引数（argv=ps 露出・CWE-214）に載せず、-K -（config を
    # stdin 渡し）で送る。BODY は秘匿情報を含まない hook メタなので従来どおり -d 引数でよい。
    if [ -n "${PHLOX_TOKEN:-}" ]; then
        printf 'header = "Authorization: Bearer %s"\n' "$PHLOX_TOKEN" \
            | curl -fsS --max-time 5 -K - -X POST -H "Content-Type: application/json" -d "$BODY" "$CLAUDE_HOOKS_URL" >/dev/null 2>&1 || true
    else
        curl -fsS --max-time 5 -X POST -H "Content-Type: application/json" -d "$BODY" "$CLAUDE_HOOKS_URL" >/dev/null 2>&1 || true
    fi

}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    hook_dispatcher_main "$@"
fi
