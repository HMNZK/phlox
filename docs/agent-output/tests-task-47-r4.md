# task-47 ハーネス検証 r4

## t47-h2

実行コマンド:

```sh
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t47-h2 swift test --no-parallel --filter PMTranscriptVisualTask47Tests)
```

出力原文（exit 1）:

```text
[1/1] Compiling plugin GenerateManual
[2/2] Compiling plugin GenerateDoccReference
Building for debugging...
[2/5] Write sources
[3/5] Write swift-version--58304C5D6DBC2206.txt
[5/7] Compiling SessionFeatureTests PMTranscriptVisualTask47Tests.swift
/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask47Tests.swift:623:28: warning: 'accessibilityActionNames()' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
621 |             return true
622 |         }
623 |         let names = object.accessibilityActionNames()
    |                            `- warning: 'accessibilityActionNames()' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
624 |         if names.contains(NSAccessibility.Action.press) {
625 |             object.accessibilityPerformAction(.press)

/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask47Tests.swift:625:20: warning: 'accessibilityPerformAction' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
623 |         let names = object.accessibilityActionNames()
624 |         if names.contains(NSAccessibility.Action.press) {
625 |             object.accessibilityPerformAction(.press)
    |                    `- warning: 'accessibilityPerformAction' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
626 |             return true
627 |         }

[#DeprecatedDeclaration]: <https://docs.swift.org/compiler/documentation/diagnostics/deprecated-declaration>
[6/7] Emitting module SessionFeatureTests
[6/8] Write Objects.LinkFileList
[7/8] Linking SessionFeaturePackageTests
Build complete! (6.02s)
Test Suite 'Selected tests' started at 2026-09-14 10:08:41.016.
Test Suite 'SessionFeaturePackageTests.xctest' started at 2026-09-14 10:08:41.018.
Test Suite 'SessionFeaturePackageTests.xctest' passed at 2026-09-14 10:08:41.018.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'Selected tests' passed at 2026-09-14 10:08:41.018.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
◇ Suite "PMTranscriptVisualTask47" started.
◇ Test "PM visual: ChatTranscriptView host for task-47" started.
✘ Test "PM visual: ChatTranscriptView host for task-47" recorded an issue at PMTranscriptVisualTask47Tests.swift:161:5: Expectation failed: (closedBefore → []).contains("折りたたみ中")
✘ Test "PM visual: ChatTranscriptView host for task-47" recorded an issue at PMTranscriptVisualTask47Tests.swift:165:5: Expectation failed: expanded
✘ Test "PM visual: ChatTranscriptView host for task-47" recorded an issue at PMTranscriptVisualTask47Tests.swift:169:5: Expectation failed: (afterOpen → []).contains("展開中")
✘ Test "PM visual: ChatTranscriptView host for task-47" recorded an issue at PMTranscriptVisualTask47Tests.swift:176:5: Expectation failed: (afterSameID → []).contains("展開中")
✘ Test "PM visual: ChatTranscriptView host for task-47" recorded an issue at PMTranscriptVisualTask47Tests.swift:188:5: Expectation failed: (afterRemount → []).contains("折りたたみ中")
✘ Test "PM visual: ChatTranscriptView host for task-47" failed after 1.222 seconds with 5 issues.
✘ Suite "PMTranscriptVisualTask47" failed after 1.222 seconds with 5 issues.
✘ Test run with 1 test in 1 suite failed after 1.223 seconds with 5 issues.
```

開閉値候補は 0 件で、値要素を特定できなかった。`closedBefore`、`afterOpen`、`afterSameID`、`afterRemount` はすべて `[]`。

## t47-h2-46

実行コマンド:

```sh
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t47-h2-46 swift test --no-parallel --filter PMTranscriptVisualTask46Tests)
```

出力原文（exit 0）:

```text
✔ Test run with 1 test in 1 suite passed after 0.454 seconds.
```
