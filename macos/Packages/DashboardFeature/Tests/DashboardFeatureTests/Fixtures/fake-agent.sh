#!/bin/bash
# Phlox E2E fake agent CLI (deterministic PTY stub).

EXIT_AFTER=-1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --exit-after)
            EXIT_AFTER="${2:-0}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

post_hook() {
    local kind="$1"
    local body

    if [[ -z "${FAKE_AGENT_HOOK_URL:-}" || -z "${PHLOX_SESSION_ID:-}" ]]; then
        return 0
    fi

    case "$kind" in
        sessionStart)
            body=$(jq -nc \
                --arg sid "$PHLOX_SESSION_ID" \
                '{sessionId: $sid, kind: "sessionStart"}')
            ;;
        stop)
            body=$(jq -nc \
                --arg sid "$PHLOX_SESSION_ID" \
                --argjson code 0 \
                '{sessionId: $sid, kind: "stop", exitCode: $code}')
            ;;
        *)
            return 0
            ;;
    esac

    curl -fsS --max-time 2 -X POST -H "Content-Type: application/json" -d "$body" "$FAKE_AGENT_HOOK_URL" >/dev/null 2>&1 || true
}

printf 'FAKE_AGENT_READY>\n'

post_hook sessionStart

if [[ "$EXIT_AFTER" -eq 0 ]]; then
    exit 0
fi

# Phlox PTY は cfmakeraw。MessagingService の submit は \r、直接 sendInput は \n。
# dd + xxd で 1 バイトずつ読み、$(...) の改行剥がしを避ける。
read_line() {
    local line="" hex
    while true; do
        hex=$(dd bs=1 count=1 2>/dev/null | xxd -p | tr -d '\n')
        [[ -z "$hex" ]] && break
        case "$hex" in
            0a|0d) break ;;
            *) line+=$(printf '%b' "\\x${hex}") ;;
        esac
    done
    printf '%s' "$line"
}

lines_processed=0
while true; do
    line=$(read_line)
    [[ -z "$line" ]] && break

    printf 'ECHO: %s\n' "$line"
    post_hook stop

    lines_processed=$((lines_processed + 1))
    if [[ "$EXIT_AFTER" -ge 0 && "$lines_processed" -ge "$EXIT_AFTER" ]]; then
        exit 0
    fi
done
