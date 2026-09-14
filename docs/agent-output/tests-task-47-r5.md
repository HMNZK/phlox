# task-47 ハーネス検証 r5

## t47-h3

実行コマンド:

```sh
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t47-h3 swift test --no-parallel --filter PMTranscriptVisualTask47Tests)
```

出力原文（exit 0）:

```text
✔ Test run with 1 test in 1 suite passed after 1.285 seconds.
```

## t47-h3-46

実行コマンド:

```sh
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t47-h3-46 swift test --no-parallel --filter PMTranscriptVisualTask46Tests)
```

出力原文（exit 0）:

```text
✔ Test run with 1 test in 1 suite passed after 0.492 seconds.
```

## t47-h3-red（期待値を一時反転）

展開操作後の本文出現期待値だけを `true` から `false` へ一時変更して実行し、直後に元へ戻した。

実行コマンド:

```sh
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t47-h3-red swift test --no-parallel --filter PMTranscriptVisualTask47Tests)
```

出力原文（exit 1）:

```text
[1/1] Compiling plugin GenerateManual
[2/2] Compiling plugin GenerateDoccReference
Building for debugging...
[2/5] Write sources
[3/5] Write swift-version--58304C5D6DBC2206.txt
[5/7] Emitting module SessionFeatureTests
[6/7] Compiling SessionFeatureTests PMTranscriptVisualTask47Tests.swift
[6/8] Write Objects.LinkFileList
[7/8] Linking SessionFeaturePackageTests
Build complete! (6.08s)
Test Suite 'Selected tests' started at 2026-09-14 10:27:47.431.
Test Suite 'SessionFeaturePackageTests.xctest' started at 2026-09-14 10:27:47.432.
Test Suite 'SessionFeaturePackageTests.xctest' passed at 2026-09-14 10:27:47.432.
	Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'Selected tests' passed at 2026-09-14 10:27:47.432.
	Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
◇ Suite "PMTranscriptVisualTask47" started.
◇ Test "PM visual: ChatTranscriptView host for task-47" started.
✘ Test "PM visual: ChatTranscriptView host for task-47" recorded an issue at PMTranscriptVisualTask47Tests.swift:563:5: Expectation failed: (texts.contains { $0.contains(fragment) } → true) == (expected → false)
↳ 展開操作後: 収集テキスト=["有効", "Markdown と思考色を確認する。", "確認結果", "太字 と 斜体", "箇条書き", "引用", "詳細", "A", "B", "x", "y", "a/**/b: error", "Bypass", "モデル"]
✘ Test "PM visual: ChatTranscriptView host for task-47" failed after 1.332 seconds with 1 issue.
✘ Suite "PMTranscriptVisualTask47" failed after 1.332 seconds with 1 issue.
✘ Test run with 1 test in 1 suite failed after 1.332 seconds with 1 issue.
```

## t47-h3（期待値復元後）

出力原文（exit 0）:

```text
✔ Test run with 1 test in 1 suite passed after 1.338 seconds.
```
