# task-47 ハーネス検証 r3

## t47-harness

実行コマンド:

```sh
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t47-harness swift test --no-parallel --filter PMTranscriptVisualTask47Tests)
```

出力原文（exit 1）:

```text
[1/1] Compiling plugin GenerateManual
[2/2] Compiling plugin GenerateDoccReference
Building for debugging...
[2/5] Write sources
[3/5] Write swift-version--58304C5D6DBC2206.txt
[5/7] Compiling SessionFeatureTests PMTranscriptVisualTask47Tests.swift
/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask47Tests.swift:585:32: warning: 'accessibilityActionNames()' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
583 |                 return true
584 |             }
585 |             let names = object.accessibilityActionNames()
    |                                `- warning: 'accessibilityActionNames()' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
586 |             if names.contains(NSAccessibility.Action.press) {
587 |                 object.accessibilityPerformAction(.press)

/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask47Tests.swift:587:24: warning: 'accessibilityPerformAction' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
585 |             let names = object.accessibilityActionNames()
586 |             if names.contains(NSAccessibility.Action.press) {
587 |                 object.accessibilityPerformAction(.press)
    |                        `- warning: 'accessibilityPerformAction' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
588 |                 return true
589 |             }

[#DeprecatedDeclaration]: <https://docs.swift.org/compiler/documentation/diagnostics/deprecated-declaration>
[6/40] Compiling SessionFeatureTests AcceptanceUserQuestionDismissTests.swift
[7/40] Compiling SessionFeatureTests AcceptanceUserQuestionSecretPersistenceTests.swift
[8/40] Compiling SessionFeatureTests AcceptanceUserQuestionStatusTests.swift
[9/40] Compiling SessionFeatureTests ChatSessionUnseenStopTests.swift
[10/40] Compiling SessionFeatureTests ChatSessionViewModelAppendDeltaTests.swift
[11/40] Compiling SessionFeatureTests ComposerFocusApplyWhiteboxTests.swift
[12/40] Compiling SessionFeatureTests AcceptanceComposerFocusRestoreTests.swift
/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceComposerFocusRestoreTests.swift:91:25: warning: main actor-isolated property 'subviews' can not be referenced from a nonisolated context
 87 | }
 88 |
 89 | private func firstTextView(in view: NSView) -> NSTextView? {
    |              `- note: add '@MainActor' to make global function 'firstTextView(in:)' part of global actor 'MainActor'
 90 |     if let textView = view as? NSTextView { return textView }
 91 |     for subview in view.subviews {
    |                         `- warning: main actor-isolated property 'subviews' can not be referenced from a nonisolated context
 92 |         if let found = firstTextView(in: subview) { return found }
 93 |     }

/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSView.h:88:46: note: property declared here
 86 | @property (nullable, readonly, unsafe_unretained) NSWindow *window;
 87 | @property (nullable, readonly, unsafe_unretained) NSView *superview;
 88 | @property (copy) NSArray<__kindof NSView *> *subviews;
    |                                              `- note: property declared here
 89 | - (BOOL)isDescendantOf:(NSView *)view;
 90 | - (nullable NSView *)ancestorSharedWithView:(NSView *)view;
[13/40] Compiling SessionFeatureTests AcceptanceGridComposerOverflowTests.swift
/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceComposerFocusRestoreTests.swift:91:25: warning: main actor-isolated property 'subviews' can not be referenced from a nonisolated context
 87 | }
 88 |
 89 | private func firstTextView(in view: NSView) -> NSTextView? {
    |              `- note: add '@MainActor' to make global function 'firstTextView(in:)' part of global actor 'MainActor'
 90 |     if let textView = view as? NSTextView { return textView }
 91 |     for subview in view.subviews {
    |                         `- warning: main actor-isolated property 'subviews' can not be referenced from a nonisolated context
 92 |         if let found = firstTextView(in: subview) { return found }
 93 |     }

/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSView.h:88:46: note: property declared here
 86 | @property (nullable, readonly, unsafe_unretained) NSWindow *window;
 87 | @property (nullable, readonly, unsafe_unretained) NSView *superview;
 88 | @property (copy) NSArray<__kindof NSView *> *subviews;
    |                                              `- note: property declared here
 89 | - (BOOL)isDescendantOf:(NSView *)view;
 90 | - (nullable NSView *)ancestorSharedWithView:(NSView *)view;
[14/40] Compiling SessionFeatureTests AcceptanceMidTurnPersistenceTests.swift
/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceComposerFocusRestoreTests.swift:91:25: warning: main actor-isolated property 'subviews' can not be referenced from a nonisolated context
 87 | }
 88 |
 89 | private func firstTextView(in view: NSView) -> NSTextView? {
    |              `- note: add '@MainActor' to make global function 'firstTextView(in:)' part of global actor 'MainActor'
 90 |     if let textView = view as? NSTextView { return textView }
 91 |     for subview in view.subviews {
    |                         `- warning: main actor-isolated property 'subviews' can not be referenced from a nonisolated context
 92 |         if let found = firstTextView(in: subview) { return found }
 93 |     }

/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSView.h:88:46: note: property declared here
 86 | @property (nullable, readonly, unsafe_unretained) NSWindow *window;
 87 | @property (nullable, readonly, unsafe_unretained) NSView *superview;
 88 | @property (copy) NSArray<__kindof NSView *> *subviews;
    |                                              `- note: property declared here
 89 | - (BOOL)isDescendantOf:(NSView *)view;
 90 | - (nullable NSView *)ancestorSharedWithView:(NSView *)view;
[15/40] Compiling SessionFeatureTests ChatEscapeHandlingWhiteboxTests.swift
[16/40] Compiling SessionFeatureTests ChatRemoteSessionNotifierTests.swift
[17/40] Compiling SessionFeatureTests ChatRevertAttachmentTests.swift
[18/40] Compiling SessionFeatureTests ComposerOverflowLayoutTests.swift
/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Harness/TranscriptTypographyRenderHarness.swift:607:24: warning: 'accessibilityActionNames()' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 605 |     }
 606 |     let object = element as AnyObject
 607 |     let names = object.accessibilityActionNames()
     |                        `- warning: 'accessibilityActionNames()' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 608 |     if names.contains(NSAccessibility.Action.press) {
 609 |         object.accessibilityPerformAction(.press)

/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Harness/TranscriptTypographyRenderHarness.swift:609:16: warning: 'accessibilityPerformAction' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 607 |     let names = object.accessibilityActionNames()
 608 |     if names.contains(NSAccessibility.Action.press) {
 609 |         object.accessibilityPerformAction(.press)
     |                `- warning: 'accessibilityPerformAction' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 610 |         return true
 611 |     }

[#DeprecatedDeclaration]: <https://docs.swift.org/compiler/documentation/diagnostics/deprecated-declaration>
[19/40] Compiling SessionFeatureTests GridComposerLayoutWhiteboxTests.swift
/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Harness/TranscriptTypographyRenderHarness.swift:607:24: warning: 'accessibilityActionNames()' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 605 |     }
 606 |     let object = element as AnyObject
 607 |     let names = object.accessibilityActionNames()
     |                        `- warning: 'accessibilityActionNames()' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 608 |     if names.contains(NSAccessibility.Action.press) {
 609 |         object.accessibilityPerformAction(.press)

/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Harness/TranscriptTypographyRenderHarness.swift:609:16: warning: 'accessibilityPerformAction' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 607 |     let names = object.accessibilityActionNames()
 608 |     if names.contains(NSAccessibility.Action.press) {
 609 |         object.accessibilityPerformAction(.press)
     |                `- warning: 'accessibilityPerformAction' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 610 |         return true
 611 |     }

[#DeprecatedDeclaration]: <https://docs.swift.org/compiler/documentation/diagnostics/deprecated-declaration>
[20/40] Compiling SessionFeatureTests TranscriptTypographyRenderHarness.swift
/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Harness/TranscriptTypographyRenderHarness.swift:607:24: warning: 'accessibilityActionNames()' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 605 |     }
 606 |     let object = element as AnyObject
 607 |     let names = object.accessibilityActionNames()
     |                        `- warning: 'accessibilityActionNames()' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 608 |     if names.contains(NSAccessibility.Action.press) {
 609 |         object.accessibilityPerformAction(.press)

/private/tmp/ui-ux-wt-47/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Harness/TranscriptTypographyRenderHarness.swift:609:16: warning: 'accessibilityPerformAction' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 607 |     let names = object.accessibilityActionNames()
 608 |     if names.contains(NSAccessibility.Action.press) {
 609 |         object.accessibilityPerformAction(.press)
     |                `- warning: 'accessibilityPerformAction' was deprecated in macOS 10.10: Use the NSAccessibility protocol methods instead (see NSAccessibilityProtocols.h) [#DeprecatedDeclaration]
 610 |         return true
 611 |     }

[#DeprecatedDeclaration]: <https://docs.swift.org/compiler/documentation/diagnostics/deprecated-declaration>
[21/43] Compiling SessionFeatureTests MidTurnPersistenceWhiteboxTests.swift
[22/43] Compiling SessionFeatureTests RemoteSessionNotifierTests.swift
[23/43] Compiling SessionFeatureTests SeedCommandsWiringWhiteboxTests.swift
[24/43] Compiling SessionFeatureTests AcceptanceNotificationGapTests.swift
[25/43] Compiling SessionFeatureTests AcceptanceRawEventLogCapTests.swift
[26/43] Compiling SessionFeatureTests AcceptanceSessionTitleLifecycleTests.swift
[27/43] Compiling SessionFeatureTests AcceptanceCodexUserInputViewModelTests.swift
[28/43] Compiling SessionFeatureTests AcceptanceCompactingIndicatorTests.swift
[29/43] Compiling SessionFeatureTests AcceptanceComposerAvailableCommandsTests.swift
[30/43] Compiling SessionFeatureTests AcceptanceSubAgentTranscriptMergeTests.swift
[31/43] Compiling SessionFeatureTests AcceptanceTaskListCardTests.swift
[32/43] Compiling SessionFeatureTests AcceptanceUserQuestionAttentionTests.swift
[33/43] Compiling SessionFeatureTests AcceptanceStopButtonPersistenceTests.swift
[34/43] Compiling SessionFeatureTests AcceptanceStreamCoalescingTests.swift
[35/43] Compiling SessionFeatureTests AcceptanceSubAgentStopParityTests.swift
[36/43] Compiling SessionFeatureTests PMTranscriptVisualTask46Tests.swift
[37/43] Compiling SessionFeatureTests AcceptanceCodexSkillPickerTests.swift
[38/43] Compiling SessionFeatureTests AcceptanceCodexUserInputDismissTests.swift
[39/43] Compiling SessionFeatureTests SubAgentControlSummaryTests.swift
[40/43] Compiling SessionFeatureTests SubAgentStopWhiteboxTests.swift
[41/43] Compiling SessionFeatureTests TranscriptStreamCoalescerWhiteboxTests.swift
[42/43] Emitting module SessionFeatureTests
[42/44] Write Objects.LinkFileList
[43/44] Linking SessionFeaturePackageTests
Build complete! (6.89s)
Test Suite 'Selected tests' started at 2026-09-14 09:51:03.179.
Test Suite 'SessionFeaturePackageTests.xctest' started at 2026-09-14 09:51:03.180.
Test Suite 'SessionFeaturePackageTests.xctest' passed at 2026-09-14 09:51:03.180.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'Selected tests' passed at 2026-09-14 09:51:03.180.
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
✘ Test "PM visual: ChatTranscriptView host for task-47" failed after 1.210 seconds with 5 issues.
✘ Suite "PMTranscriptVisualTask47" failed after 1.210 seconds with 5 issues.
✘ Test run with 1 test in 1 suite failed after 1.210 seconds with 5 issues.
```

SIGABRT / signal 6 は発生しなかった。残る RED は開閉値アサーションの期待値不一致。

## t47-harness-46

実行コマンド:

```sh
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t47-harness-46 swift test --no-parallel --filter PMTranscriptVisualTask46Tests)
```

出力原文（exit 0）:

```text
✔ Test run with 1 test in 1 suite passed after 0.465 seconds.
```
