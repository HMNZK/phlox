---
task: task-37
status: completed
---
## 詰まった / 完了できなかった点

なし。配線検査・AgentConfigKit テスト・隔離 Debug App ビルドはいずれも exit 0。アプリ起動・AX 目視は契約の PM ゲートであり、実装指示で起動不要と明示されたため未実施。

## できた風だが実は未完（最重要）

- 状態ペインの実画面は未確認。先頭要約・DisclosureGroup 初回閉・展開後のバージョン/パス・閉じても要約が残ること・長いパスの省略とコピーは、ソース配線と凍結テスト／Ruby 検査まで。AXPress 撮影は PM 目視ゲート。
- CLI 検出×設定ファイル有無の 4 組は `AcceptanceAgentConsoleStatusSummaryTests` のリテラル比較のみ。GUI では実環境の 1 状態しか見えない。負例のために CLI/設定を消していない（契約どおり）。
- `configurationDetail` が nil のときは詳細行を出さない（`if let`）。空文字の Text は置いていない。
- DisclosureGroup は標準コントロールのまま。旧「CLI」節の `terminal` アイコンはラベルに付けていない。見た目の差は未撮影。
- 要約 UI は 3 ペインに同じ VStack を複製している。パッケージ側に View を置けない制約のため。見た目の修正は 3 箇所になる。
- messageBar のエラー表示はこのタスク範囲外（task-36）。折りたたんでいないことは、状態ペインが messageBar を持たない現状の維持でしか担保していない。

## 置いた前提・仮定

- `make(isAvailable:configFileExists:)` の実引数は契約の識別子と完全一致。Claude は `model.isClaudeAvailable` と `model.status.settingsFileExists`、Codex/Cursor は `model.isAvailable` と `model.status.configFileExists`。追加演算なし。検出根拠は既存 ConsoleModel（Claude は `pluginService != nil`、Codex/Cursor は `executablePath != nil`）を読んだだけで、Model は変更していない。
- 要約は認証・通信成功を意味しない文言（「検出済み」「認証・通信の状態は未確認です」）とし、未作成設定は `DSColor.statusError` にしない。設定節の既存 `note: "未作成"` はそのまま。
- 本文順は要約 4 フィールド → `summaryTiles` → DisclosureGroup（旧 CLI 2 行）→ 設定節 → メモリ（Cursor は認証情報の説明）。toolbar / 設定節 / Finder / 再読み込み / `loadMCPServers()` は baseline `094f86a` から未変更。
- `@State private var showsCLIDetails = false` で初回は閉じる。展開内容は既存のバージョン（未取得は `"—"`）と実行ファイルパス（`mono:` による省略とコピー）。
- `AgentConsoleStatusSummary` は SwiftUI/AppKit/I/O 非依存。公開 API は `make` と 5 フィールド。メンバワイズ init は内部のまま。
- SettingsView / AgentConsoleWindowView / AgentConsoleSection / ConsoleModel / custom agents.json 系統は未変更。

## 契約からの逸脱

なし。変更ファイルは allowed_paths のみ（新設 `AgentConsoleStatusSummary.swift`、3 StatusPane、本レポート）。テスト・Ruby・契約・台帳は未変更。

## App ビルド結果（xcodebuild 末尾）

```
Validate /tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app (in target 'Phlox' from project 'Phlox')
    cd /Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos
    builtin-validationUtility /tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app -no-validate-extension -infoplist-subpath Contents/Info.plist

RegisterWithLaunchServices /tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app (in target 'Phlox' from project 'Phlox')
    cd /Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app

note: Disabling hardened runtime with ad-hoc codesigning. (in target 'Phlox' from project 'Phlox')
note: Run script build phase 'Re-register Debug app with LaunchServices (Dock display name)' will be run during every build because the option to run the script phase "Based on dependency analysis" is unchecked. (in target 'Phlox' from project 'Phlox')
** BUILD SUCCEEDED **
```

`TASK37_BASELINE=094f86a ruby .claude/scripts/task37-wiring.rb` OK（`--selftest` も OK）。`cd macos/Packages/AgentConfigKit && swift test` 89 tests passed（うち task-37 受け入れ 2）。`git diff --check` 空。

## レビュー重点（PM 用）

- CLI 検出を認証済みと読める色・文言にしていないか。設定未作成をエラー扱いにしていないか（要約は textPrimary/textTertiary。設定節の既存「未作成」note は残置）。
- 旧 CLI 節が DisclosureGroup 外に残っていないか。バージョン `"—"` とパスの `mono:` が展開内にあるか。初回 `$showsCLIDetails = false` か。
- toolbar・設定節・summaryTiles・メモリ・Finder・Claude 再読み込み・Codex `loadMCPServers()`・Cursor 認証情報説明が `094f86a` から欠落していないか（Ruby は compact 比較。意味の退行は目視）。
- make 実引数が契約と文字どおり一致しているか。StatusPane 以外（WindowView / Settings / ConsoleModel）への漏れ変更が無いか。
- 実機では標準ウィンドウ寸法で、help「エージェント管理」から 3 状態ペインを開き、先頭要約と CLI 詳細の開閉を撮影すること。
=== REPORT COMPLETE ===
