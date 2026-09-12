#!/usr/bin/env bash
set -euo pipefail
# driver正規のVERIFY_TASK_BIN拡張。個別タスクを検査し、最終統合のverify.shは変更しない。
verifier=/Users/ryosuke/.agents/skills/agentic-loop/scripts/agentic-loop-verify-task.sh
if [ "${1:-}" = task-8 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test --full task8-ui bash macos/scripts/test-view-mode-accessibility.sh && git diff --check'
fi
if [ "${1:-}" = task-17 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test --full task17-ui bash macos/scripts/test-settings-buttons-acceptance.sh && git diff --check'
fi
if [ "${1:-}" = task-27 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task27-wiring ruby .claude/scripts/task27-wiring.rb && (cd macos/Packages/DesignSystem && /Users/ryosuke/.agents/scripts/compact-test task27-design-system swift test) && git diff --check'
fi
if [ "${1:-}" = task-13 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task13-wiring ruby .claude/scripts/task13-wiring.rb && (cd macos/Packages/DesignSystem && /Users/ryosuke/.agents/scripts/compact-test task13-design-system swift test --filter AcceptanceSidebarTextContrastTests) && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task13-dashboard swift build) && git diff --check'
fi
if [ "${1:-}" = task-28 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task28-wiring ruby .claude/scripts/task28-wiring.rb && (cd macos/Packages/TerminalUI && /Users/ryosuke/.agents/scripts/compact-test task28-terminal-ui swift test) && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task28-session-feature swift build) && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task28-dashboard swift build) && git diff --check'
fi
if [ "${1:-}" = task-29 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task29-wiring ruby .claude/scripts/task29-wiring.rb && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task29-dashboard swift test --filter "AcceptanceUsageRemainingSummaryTests|UsageDisplayTests|AcceptanceUsageBarUnificationTests") && git diff --check'
fi
if [ "${1:-}" = task-30 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task30-wiring ruby .claude/scripts/task30-wiring.rb && (cd macos/Packages/DesignSystem && /Users/ryosuke/.agents/scripts/compact-test task30-design-system swift test) && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task30-dashboard swift build) && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task30-session swift build) && git diff --check'
fi
if [ "${1:-}" = task-26 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task26-process-groups ruby .claude/scripts/task26-process-groups.rb && git diff --check'
fi
if [ "${1:-}" = task-31 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task31-wiring ruby .claude/scripts/task31-wiring.rb && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task31-dashboard swift test) && git diff --check'
fi
if [ "${1:-}" = task-32 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task32-wiring ruby .claude/scripts/task32-wiring.rb && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task32-dashboard swift test) && git diff --check'
fi
if [ "${1:-}" = task-33 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task33-wiring env TASK33_BASELINE=c615c0a ruby .claude/scripts/task33-wiring.rb && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task33-dashboard swift test) && git diff --check'
fi
if [ "${1:-}" = task-34 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task34-wiring env TASK34_BASELINE=40533aa ruby .claude/scripts/task34-wiring.rb && (cd macos/Packages/DesignSystem && /Users/ryosuke/.agents/scripts/compact-test task34-design-system swift test) && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task34-dashboard swift build) && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task34-session swift build) && git diff --check'
fi
exec bash "$verifier" "$@"
