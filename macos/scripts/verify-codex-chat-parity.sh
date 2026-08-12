#!/usr/bin/env bash
# Codex chat parity の Phase 1 検証。
# CodexAppServerKit の凍結/基盤テストと SessionFeature 全件を UI E2E なしで実行する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CODEX_PACKAGE="$REPO_ROOT/macos/Packages/CodexAppServerKit"
SESSION_PACKAGE="$REPO_ROOT/macos/Packages/SessionFeature"
DASHBOARD_PACKAGE="$REPO_ROOT/macos/Packages/DashboardFeature"
CODEX_FILTER='AcceptanceCodex|ContractCodex'
SESSION_BACKGROUND_TERMINAL_FILTER='AcceptanceCodexBackgroundTerminalStateTests'
DASHBOARD_FILTER='AcceptanceCodex.*Route|Codex.*Route'

test_count() {
    # Swift Testing と XCTest のどちらのサマリでも実行件数を拾う。
    awk '
        /Test run with [0-9]+ tests?/ {
            for (i = 1; i <= NF; i++) {
                if (!swift_seen && $i == "with" && $(i + 1) ~ /^[0-9]+$/ && $(i + 2) ~ /^tests?$/) {
                    swift_count = $(i + 1)
                    swift_seen = 1
                }
            }
        }
        /Executed [0-9]+ tests?/ {
            for (i = 1; i <= NF; i++) {
                if (!xctest_seen && $i == "Executed" && $(i + 1) ~ /^[0-9]+$/ && $(i + 2) ~ /^tests?/) {
                    xctest_count = $(i + 1)
                    xctest_seen = 1
                }
            }
        }
        END {
            if (swift_seen) print swift_count + 0
            else if (xctest_seen) print xctest_count + 0
            else print 0
        }
    ' "$1"
}

run_package() {
    local label="$1"
    local package_path="$2"
    shift 2
    local log status count

    if [ ! -f "$package_path/Package.swift" ]; then
        echo "verify-codex-chat-parity: package が見つかりません: $package_path" >&2
        return 1
    fi

    log="$(mktemp -t phlox-codex-parity-run.XXXXXX)"
    echo "=== swift test --package-path $package_path $* ==="
    if swift test --package-path "$package_path" "$@" >"$log" 2>&1; then
        status=0
    else
        status=$?
    fi

    count="$(test_count "$log")"
    if [ "$count" -eq 0 ]; then
        echo "FAIL: $label (tests=0, 実行テスト件数が0です)" >&2
        tail -100 "$log" >&2
        rm -f "$log"
        [ "$status" -eq 0 ] && return 1
        return "$status"
    fi

    if [ "$status" -ne 0 ]; then
        echo "FAIL: $label (tests=$count, exit=$status)" >&2
        tail -100 "$log" >&2
        rm -f "$log"
        return "$status"
    fi

    echo "PASS: $label (tests=$count, exit=0)"
    rm -f "$log"
    return 0
}

failed=0

if run_package "CodexAppServerKit 凍結/基盤" "$CODEX_PACKAGE" --filter "$CODEX_FILTER" --no-parallel; then
    :
else
    failed=$?
fi

if run_package "SessionFeature Codex background terminal state (parallel)" "$SESSION_PACKAGE" \
    --filter "$SESSION_BACKGROUND_TERMINAL_FILTER" --parallel; then
    :
else
    session_parallel_status=$?
    [ "$failed" -ne 0 ] || failed="$session_parallel_status"
fi

if run_package "SessionFeature 全suite" "$SESSION_PACKAGE" --no-parallel; then
    :
else
    session_status=$?
    [ "$failed" -ne 0 ] || failed="$session_status"
fi

if run_package "DashboardFeature Codex route" "$DASHBOARD_PACKAGE" --filter "$DASHBOARD_FILTER" --no-parallel; then
    :
else
    dashboard_status=$?
    [ "$failed" -ne 0 ] || failed="$dashboard_status"
fi

if [ "$failed" -ne 0 ]; then
    echo "verify-codex-chat-parity: FAILED (exit=$failed)" >&2
    exit "$failed"
fi

echo "verify-codex-chat-parity: OK"
