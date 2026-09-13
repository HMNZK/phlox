---
task: task-46
status: completed
---

# task-46 PM 目視ハーネス修理（r4）

対象は `macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask46Tests.swift` のみ。製品・凍結テスト・rb・契約・台帳は未変更。固定シナリオのアサーションは未変更。

## 変更行と理由

- コメント 5 行付近: 窓表示モードの `PHLOX_PM_VISUAL_WIDTH` / `SCALE` / `THEME` を明記。
- 44〜53 行: `showWindow` のとき、最初の `NSWindow` より前に `NSApplication.shared` を取り、元の `activationPolicy` を保存して `.regular` にし、`finishLaunching()` と `NSApp.activate(ignoringOtherApps: true)` を行う。policy だけを窓直前で変えると CG 窓は出ても AX は `-25204` のまま（System Events は `background only=false` でも `nwin=0`）。`NSApp` を shared 初期化前に触ると nil unwrap で SIGTRAP する。
- 73〜75 / 109〜116 行: ルート View 既存の `.preferredColorScheme` に加え、`NSHostingView` と `NSWindow` の `appearance`（aqua / darkAqua）を明示。表示直前にも policy を再設定し、`makeKeyAndOrderFront` のあと `orderFrontRegardless` と再 `activate`。
- 176〜177 行: 終了時に保存した policy へ戻す。
- 181〜217 行: 窓表示モードのみ幅 360|720・倍率 0.8|1.0|2.0・テーマ light|dark を読み、`scenario.columnWidth` / `ChatFontSettings.save(defaults: suite)` / `ThemeStore.themeKey` / `scenario.colorScheme` へ反映。不正値は `#expect` で落とす。未設定は既定 720 / 1.0 / light。環境変数なしの通常実行は従来と同じ入力。
- **`UserDefaults.standard` への `ThemeStore.themeKey` 書き込み（30〜31 行と 171〜175 行の復元、および `applyLightTheme` / `applyDarkTheme`）は撤去保留。** `@AppStorage(ThemeStore.themeKey)` を使う View（`ChatTranscriptView`、各 `ChatMessageCells*`、`ChatComposer` 経路）は `.defaultAppStorage(suite)` で suite を読む。一方 **`DSColor` は View ではなく `ThemeStore.active`（`UserDefaults.standard`）固定**、`ChatMessageRenderCache` のハイライト／diff／コマンド表示も `ThemeStore.active.id` をキーにする。ルートの `.background(DSColor.chatBackground)` も standard 依存。製品は変えないため suite 注入だけではカード色・背景・コード色が追従しない。

## 検証原文

```
$ ruby .claude/scripts/task46-wiring.rb --selftest
task46-wiring --selftest: OK
exit_code: 0

$ (cd macos/Packages/SessionFeature && env -u PHLOX_PM_VISUAL_TASK -u PHLOX_PM_VISUAL_WIDTH -u PHLOX_PM_VISUAL_SCALE -u PHLOX_PM_VISUAL_THEME ~/.agents/scripts/compact-test t46-h2 swift test --no-parallel --filter PMTranscriptVisualTask46Tests)
✔ Test run with 1 test in 1 suite passed after 0.512 seconds.
exit_code: 0
```

窓表示（nohup、cwd=`macos/Packages/SessionFeature`、Release Phlox PID 61465 は未操作、キー入力なし）:

```
env PHLOX_PM_VISUAL_TASK=46 PHLOX_PM_VISUAL_WIDTH=360 PHLOX_PM_VISUAL_SCALE=2.0 PHLOX_PM_VISUAL_THEME=dark
~/.agents/scripts/compact-test t46-h2 swift test --no-parallel --filter PMTranscriptVisualTask46Tests
```

表示ホスト PID **99546**（`swiftpm-testing-helper`）。CGWindow: name=`task-46 PM visual` bounds Width=360 Height=932。NSRunningApplication: activationPolicy=0（regular） active=True。

System Events 原文:

```
swiftpm-testing-helper, false, true, false, 1, 2
```

`AXUIElementCreateApplication(99546)` 原文:

```
probe pid=99546 trusted=True
AXRole err=0 val=AXApplication
AXTitle err=0 val=swiftpm-testing-helper
AXWindows err=0 n=1 raw=(
    "<AXUIElement 0x7451f85d0> {pid=99546}"
)
AXChildren err=0 val=(
    "<AXUIElement 0x7451f85a0> {pid=99546}",
    "<AXUIElement 0x7451f8570> {pid=99546}"
)
AXFocusedWindow err=0 val=<AXUIElement 0x7451f8510> {pid=99546}
AXWindows_count=1
window idx=1 title=task-46 PM visual role=AXWindow
AXDisclosureTriangle_count=8
TRIANGLE n=0 D2 role=AXDisclosureTriangle title= desc=処理の詳細（1件）, 出力あり value=False ident=Task46.singleCommandPath sub=
TRIANGLE n=1 D3 role=AXDisclosureTriangle title= desc=思考の詳細, 短い思考 value=False ident= sub=
TRIANGLE n=2 D3 role=AXDisclosureTriangle title= desc=思考の詳細, 思考の本文を長く書いて折りたたみと展開を見る。思考の本文を長く書いて折りたたみと展開を見る。思考の本文を長く書いて折りた… value=False ident= sub=
TRIANGLE n=3 D3 role=AXDisclosureTriangle title= desc=処理の詳細（1件）, 出力あり value=False ident=CommandGroupCell sub=
TRIANGLE n=4 D3 role=AXDisclosureTriangle title= desc=処理の詳細（51件）, 出力あり value=False ident=CommandGroupCell sub=
TRIANGLE n=5 D3 role=AXDisclosureTriangle title= desc=編集済み TranscriptItemPresentation.swift, +501, -0 value=False ident= sub=
TRIANGLE n=6 D3 role=AXDisclosureTriangle title= desc=タスク（0件） value=False ident=ChatMessage.taskList sub=
TRIANGLE n=7 D3 role=AXDisclosureTriangle title= desc=タスク（2件） value=False ident=ChatMessage.taskList sub=
```

終了: `AXCloseButton` へ AXPress（キー入力なし）。`pressed-close err=0`。CG 窓消滅、helper 消滅。テストログ:

```
✔ Test run with 1 test in 1 suite passed after 41.010 seconds.
exit_code: 0
```

PID 61465 `/Applications/Phlox.app` は終了後も残存。

=== REPORT COMPLETE ===
