---
status: completed
last-verified: 2026-08-01
---

# 0030 セッションタイルの UX 2 件（サブエージェントタブを閉じる／タイル内クリックで即選択）

run: `session-tab-ux`（agentic-loop multi・backend=codex）／ブランチ `feature/session-tab-ux`

## 何を直したか

| # | 症状 | 直した内容 |
|---|---|---|
| task-1 | サブエージェントがエラー終了するとタブが残り続け、消す手段がなかった | タブをホバーすると閉じるボタンが出て、ストリップから取り除けるようにした（[ADR 0152](../adr/0152-subagent-strip-dismiss.md)） |
| task-2 | タイルの本文（ターミナル・トランスクリプト・入力欄）をクリックしてもセッションが選択されず、ヘッダーを狙う必要があった | タイル矩形内の左マウスダウンで即選択するようにした。イベントは消費せず素通しするので既存のマウス操作は維持（[ADR 0153](../adr/0153-pane-tile-click-selection.md)） |

赤枠（要注意）は「非選択」の印ではなく「承認待ち・質問待ち」の印なので、選択しても残る（`SessionAttentionPolicy` は変更していない）。ゲート①でユーザーが現仕様維持を選択した。

## 生成・更新したドキュメント

- ADR: [0152](../adr/0152-subagent-strip-dismiss.md)（閉じるの線引き）／[0153](../adr/0153-pane-tile-click-selection.md)（クリック選択の入力経路）
- architecture: [chat-subagent-display.md](../architecture/chat-subagent-display.md)（ストリップの節）／[session-pane-layout.md](../architecture/session-pane-layout.md)（コンポーネント表・描画の制約・テスト表）

## 主な成果物

| 種別 | ファイル |
|---|---|
| 実装 | `SessionFeature/ChatSubAgentModel.swift`（`dismissSubAgent`）・`ChatSessionAccessories.swift`（閉じるボタン）・`ChatSessionViewModel.swift`・`ChatSessionView.swift`・`GridChatColumn.swift` |
| 実装 | `SessionFeature/PaneTileClickSelection.swift`（新規: Policy / Selector / Observer / FrameSource / FrameReader）・`PaneLayoutView.swift` |
| 凍結テスト | `DashboardFeatureTests/AcceptanceSubAgentDismissTests.swift`・`SessionFeatureTests/AcceptancePaneTileClickSelectionTests.swift`・`SessionFeatureTests/AcceptancePaneTileClickPassthroughTests.swift` |

## 検証結果

- `swift test --package-path macos/Packages/DashboardFeature`: **1565 tests pass**
- `swift test --package-path macos/Packages/SessionFeature`: **768 tests pass**
- `xcodebuild -project macos/Phlox.xcodeproj -scheme Phlox -configuration Debug build`: **BUILD SUCCEEDED**（別 derivedDataPath。稼働中のリリース版は終了させていない）
- 実機（Debug 版をリリース版と併存起動し、CGEvent の実マウス相当イベントで操作して目視確認）:
  - タイル本文（トランスクリプトの空白領域）をクリック → そのセッションが選択された（サイドバーの選択とタイルの選択枠が移動）
  - 別タイルの入力欄をクリック → そのセッションが選択され、キャレットも入力欄に入った
  - サブエージェントを 1 体起動 → ストリップにタブが出る。**非ホバー時は × 非表示／ホバーで × 表示（タブ内に収まりタブ名のクリップなし）／× クリックでタブが消える**。ターンを中断して `.failed`（⚠）にした状態でも同じ挙動
  - 入力欄のテキストをドラッグ選択 → 選択ハイライトが出る。トランスクリプト本文のドラッグ選択も従来どおり動く
  - タイル上でのスクロール → 内容がスクロールする
  - タイルヘッダーからのドラッグ移動 → タイル配置が変わる（ドラッグ＆ドロップが従来どおり開始する）
- 検証手段の注意: System Events の `click at` はアクセシビリティ経由の擬似クリックで、`NSEvent` のローカル監視や `NSView.mouseDown` には届かない（実測）。実機確認は Quartz の `CGEventPost(kCGHIDEventTap, …)` で行うこと。

## 差し戻しの経緯（レビューで捕まえたもの）

- task-1 r1: 閉じるボタン追加時に padding/background を Button の label 外へ出したため、タブ選択のクリック領域が縮小する退行 → `contentShape` の適用位置を直して解消。
- task-2 r1: タイル矩形を push キャッシュしていたため、原点だけが変わる `.swap` で陳腐化し別セッションを誤選択しうる → クリックごとの pull へ変更。
- task-2 r2: 「イベントを消費しない」不変条件を守るテストが 0 件（`return nil` にしても全 green）→ 契約の不足と裁定し、PM が `AcceptancePaneTileClickPassthroughTests` を追加して再凍結（`decision-log` 参照）。
