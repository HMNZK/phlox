#!/usr/bin/env bash
set -euo pipefail
# driver正規のVERIFY_TASK_BIN拡張。個別タスクを検査し、最終統合のverify.shは変更しない。
verifier=/Users/ryosuke/.agents/skills/agentic-loop/scripts/agentic-loop-verify-task.sh
if [ "${1:-}" = task-8 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test --full task8-ui bash macos/scripts/test-view-mode-accessibility.sh && git diff --check'
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
if [ "${1:-}" = task-17 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task17-wiring-selftest ruby .claude/scripts/task17-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task17-wiring env TASK17_BASELINE=4ef83d4 ruby .claude/scripts/task17-wiring.rb && git diff --check'
fi
if [ "${1:-}" = task-40 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task40-wiring-selftest ruby .claude/scripts/task40-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task40-wiring env TASK40_BASELINE=bdbf1d9 TASK40_RB_BASELINE=9883e66 ruby .claude/scripts/task40-wiring.rb && (cd macos/Packages/DesignSystem && /Users/ryosuke/.agents/scripts/compact-test task40-design-system swift test) && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task40-session swift test) && git diff --check'
fi
if [ "${1:-}" = task-41 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task41-wiring-selftest ruby .claude/scripts/task41-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task41-wiring env TASK41_BASELINE=962ddb2 TASK41_SCOPE_CHECK=1 ruby .claude/scripts/task41-wiring.rb && (cd macos/Packages/AgentDomain && /Users/ryosuke/.agents/scripts/compact-test task41-agent-domain swift test) && git diff --check'
fi
if [ "${1:-}" = task-34 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task34-wiring env TASK34_BASELINE=40533aa ruby .claude/scripts/task34-wiring.rb && (cd macos/Packages/DesignSystem && /Users/ryosuke/.agents/scripts/compact-test task34-design-system swift test) && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task34-dashboard swift build) && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task34-session swift build) && git diff --check'
fi
if [ "${1:-}" = task-35 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task35-wiring env TASK35_BASELINE=094f86a ruby .claude/scripts/task35-wiring.rb && (cd macos/Packages/DesignSystem && /Users/ryosuke/.agents/scripts/compact-test task35-design-system swift test) && git diff --check'
fi
if [ "${1:-}" = task-36 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task36-wiring env TASK36_BASELINE=74b38fe ruby .claude/scripts/task36-wiring.rb && (cd macos/Packages/AgentConfigKit && /Users/ryosuke/.agents/scripts/compact-test task36-agent-config swift test) && git diff --check'
fi
if [ "${1:-}" = task-37 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task37-wiring env TASK37_BASELINE=094f86a ruby .claude/scripts/task37-wiring.rb && (cd macos/Packages/AgentConfigKit && /Users/ryosuke/.agents/scripts/compact-test task37-agent-config swift test) && git diff --check'
fi
if [ "${1:-}" = task-43 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task43-wiring-selftest ruby .claude/scripts/task43-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task43-wiring env TASK43_BASELINE=026ed2d ruby .claude/scripts/task43-wiring.rb && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task43-session swift test) && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task43-dashboard swift test) && git diff --check'
fi
if [ "${1:-}" = task-44 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task44-wiring-selftest ruby .claude/scripts/task44-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task44-wiring env TASK44_BASELINE=b92e1db ruby .claude/scripts/task44-wiring.rb && SWIFT_TEST_SERIAL_PACKAGES="DashboardFeature SessionFeature" /Users/ryosuke/.agents/scripts/compact-test task44-swift-tests bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature && git diff --check'
fi
if [ "${1:-}" = task-46 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task46-wiring-selftest ruby .claude/scripts/task46-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task46-wiring env TASK46_BASELINE=9b93efc TASK46_SCOPE_CHECK=1 ruby .claude/scripts/task46-wiring.rb && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task46-sessionfeature swift test --no-parallel) && git diff --check'
fi
if [ "${1:-}" = task-51 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task51-wiring-selftest ruby .claude/scripts/task51-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task51-wiring env TASK51_BASELINE=57a8092 ruby .claude/scripts/task51-wiring.rb && (cd macos/Packages/DashboardFeature && /Users/ryosuke/.agents/scripts/compact-test task51-dashboardfeature swift test) && git diff --check'
fi
if [ "${1:-}" = task-49 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task49-wiring-selftest ruby .claude/scripts/task49-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task49-wiring env TASK49_BASELINE=5a5e647 ruby .claude/scripts/task49-wiring.rb && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task49-sessionfeature swift test --no-parallel) && git diff --check'
fi
if [ "${1:-}" = task-48 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task48-wiring-selftest ruby .claude/scripts/task48-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task48-wiring env TASK48_BASELINE=91cdbe9 ruby .claude/scripts/task48-wiring.rb && SWIFT_TEST_SERIAL_PACKAGES="DashboardFeature SessionFeature" /Users/ryosuke/.agents/scripts/compact-test task48-swift-tests bash macos/scripts/run-swift-tests.sh DesignSystem SessionFeature DashboardFeature && git diff --check'
fi
if [ "${1:-}" = task-45 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task45-wiring-selftest ruby .claude/scripts/task45-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task45-wiring env TASK45_BASELINE=e3dd2fb45aeec5d305995826885e15663a9dd6be ruby .claude/scripts/task45-wiring.rb && /Users/ryosuke/.agents/scripts/compact-test task45-task44-regression env TASK44_BASELINE=b92e1db ruby .claude/scripts/task44-wiring.rb && SWIFT_TEST_SERIAL_PACKAGES="DashboardFeature SessionFeature" /Users/ryosuke/.agents/scripts/compact-test task45-swift-tests bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature && git diff --check'
fi
if [ "${1:-}" = task-47 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task47-wiring-selftest ruby .claude/scripts/task47-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task47-wiring env TASK47_BASELINE=9c0ab65 TASK47_SCOPE_CHECK=0 ruby .claude/scripts/task47-wiring.rb && /Users/ryosuke/.agents/scripts/compact-test task47-task46-regression env TASK46_BASELINE=9b93efc TASK46_SCOPE_CHECK=0 ruby .claude/scripts/task46-wiring.rb && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task47-sessionfeature swift test --no-parallel) && git diff --check'
fi
if [ "${1:-}" = task-50 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task50-wiring-selftest ruby .claude/scripts/task50-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task50-wiring env TASK50_BASELINE=17c2532 ruby .claude/scripts/task50-wiring.rb && /Users/ryosuke/.agents/scripts/compact-test task50-task48-regression env TASK48_BASELINE=91cdbe9 ruby .claude/scripts/task48-wiring.rb && (cd macos/Packages/DesignSystem && /Users/ryosuke/.agents/scripts/compact-test task50-designsystem swift test) && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task50-sessionfeature swift build) && (cd macos && /Users/ryosuke/.agents/scripts/compact-test task50-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t50-verify -destination platform=macOS build) && git diff --check'
fi
exec bash "$verifier" "$@"
if [ "${1:-}" = task-38 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task38-wiring-selftest ruby .claude/scripts/task38-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task38-wiring env TASK38_BASELINE=8e628e5 ruby .claude/scripts/task38-wiring.rb && /Users/ryosuke/.agents/scripts/compact-test task38-task35-regression env TASK35_BASELINE=094f86a ruby .claude/scripts/task35-wiring.rb && (cd macos/Packages/DesignSystem && /Users/ryosuke/.agents/scripts/compact-test task38-design-system swift test) && git diff --check'
fi
if [ "${1:-}" = task-39 ]; then
  exec bash "$verifier" "$@" --verify '/Users/ryosuke/.agents/scripts/compact-test task39-wiring-selftest ruby .claude/scripts/task39-wiring.rb --selftest && /Users/ryosuke/.agents/scripts/compact-test task39-wiring env TASK39_BASELINE=521e838 ruby .claude/scripts/task39-wiring.rb && /Users/ryosuke/.agents/scripts/compact-test task39-terminalui bash macos/scripts/run-swift-tests.sh TerminalUI && (cd macos/Packages/SessionFeature && /Users/ryosuke/.agents/scripts/compact-test task39-session swift build) && git diff --check'
fi
