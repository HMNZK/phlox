---
status: completed
last-verified: 2026-07-15
---

# 0002: モバイル UI 刷新 wave-4（6タスク）作業ログ

> **このファイルの役割**: この run（`task/mobile-projects-ui`、`f4ddd55`〜`67449e0`、wave-4 task-1〜task-6 ＋ phase-4）で何をしたかの記録・状態スナップショット。
> **書かないもの**: 恒久仕様・現行構成（→ 生成した adr/architecture の各リンク先）。

## 依頼内容（7項目）

①概要（俯瞰）タブの廃止 ②新規タスク（spawn）画面の廃止とセッション一覧からのドラフト compose フローへの統合 ③ロック/ホーム画面ウィジェット（WidgetKit 拡張）の追加 ④入力欄内モデルセレクタチップの復活（wave-3 のトップバー集約からの見直し） ⑤セッション一覧の「Projects」への刷新 ⑥入力バーのキーボード「完了」ツールバー廃止 ⑦チャットメッセージコピーの長押し（contextMenu）化。

## 何をしたか（task-1〜task-6 ＋ phase-4）

- **task-1**（`Features/AppShell`・`Features/Navigation`）: `AppTab` から `.overview` を除去し3タブ化（→ [adr/0007](../adr/0007-remove-overview-tab.md)）。`SpawnView`/`SpawnViewModel`/`Route.spawn` を削除し `Route.sessionComposeDraft(project:)` を新設、セッション一覧の追加導線 seam を用意（→ [adr/0008](../adr/0008-spawn-screen-to-draft-compose.md)）。波及した既存テスト（4タブ主張・overview トグル・spawn 依存）を PM 裁定で supersede/削除（decision-log.md task-1 波及テスト処理）。
- **task-2**（`Features/SessionList`）: セッション一覧を「Projects」へ刷新（タイトル改名・件数/host subtitle 撤去・上部空白撤去・右下 FAB 撤去・各プロジェクト末尾に「+ セッションを追加」行）。
- **task-3**（`DesignSystemIOS/DSInputBar`）: キーボード上「完了」ツールバーを撤去し `.scrollDismissesKeyboard(.interactively)` へ委譲。`modelSelector` `@ViewBuilder` スロットを新設。旧凍結テスト（`providesKeyboardDismissAffordance` 主張）を新契約へ supersede（decision-log.md task-3 波及テスト処理）。
- **task-4**（`Features/SessionDetail`）: ドラフト compose の実 UI 化（`prepareDraft`/`sendMessage(composeDraft:)` の spawn→ready→send 順序制御、`ModelPickerEntry`/`ModelPickerSheet`、モデル→kind 解決）。入力欄内モデルセレクタチップを復活（`providesModelSelectorChip` false→true、→ [adr/0010](../adr/0010-restore-inline-model-selector-chip.md)）。wave-3 のチップ不在凍結テストを新契約へ supersede（decision-log.md task-4 波及テスト処理）。task-1 が残した phantom polling（存在しない `draft-compose` を 3秒毎 polling）ハザードを `isAwaitingInitialSpawn` ガードで解消。
- **task-5**（`DesignSystemIOS/DSChatBubble`）: チャットコピーを常時表示ボタンから長押し `contextMenu`（`ChatMessageCopyText`）へ変更。
- **task-6**（`ios/PhloxWidget` 新設・`PhloxCore/Shared`）: WidgetKit 拡張＋App Group（`group.com.phlox.mobile`）共有ストア／ライタを追加（→ [adr/0009](../adr/0009-widgetkit-app-group-session-status.md)）。stage-2 レビューで検出された「起動時の空配列上書きでウィジェットが潰れる」HIGH を PM が `guard !sessions.isEmpty` で修正。
- **phase-4**（統合）: task-2（全件 attention で追加導線が消えるギャップ）修正、XCUITest/スクリーンショットテストを wave-4 UI 変更（spawn 撤去・overview 撤去・完了ツールバー撤去・タイトル Projects 化・FAB 撤去・モデルチップ復活）へ整合。

## 生成・更新した永続ドキュメント

- [ios/docs/adr/0007-remove-overview-tab.md](../adr/0007-remove-overview-tab.md)（概要タブ廃止、ADR-0006 の一部を差し替え）
- [ios/docs/adr/0008-spawn-screen-to-draft-compose.md](../adr/0008-spawn-screen-to-draft-compose.md)（spawn 画面廃止→ドラフト compose、spawn→ready→send 順序制御）
- [ios/docs/adr/0009-widgetkit-app-group-session-status.md](../adr/0009-widgetkit-app-group-session-status.md)（WidgetKit 拡張＋App Group 共有設計、既知の実機ビルドブロッカーを含む）
- [ios/docs/adr/0010-restore-inline-model-selector-chip.md](../adr/0010-restore-inline-model-selector-chip.md)（入力欄内モデルセレクタチップ復活、wave-3 決定の部分見直し）
- [ios/docs/adr/0006-appshell-custom-tab-bar.md](../adr/0006-appshell-custom-tab-bar.md)（冒頭に ADR-0007 への superseded 追記のみ。独自タブバー採用の核心判断は無改変）
- [ios/docs/architecture/overview.md](../architecture/overview.md)（`PhloxWidget`/`SharedSessionStore`/`SharedSessionWriter` の追加、ドラフト compose フロー、Projects 刷新、AppShell 3タブ化、DSInputBar/DSChatBubble の現行契約を反映）

## 検証結果（run 内で実施・decision-log.md の記録に基づく）

- verify.sh green（swift test 全数・raw 値 lint）の記録が task-2/4/6 の各裁定エントリに残っている（例: task-2 MEDIUM 修正後「324/0・ビルド exit 0」、task-6「318/0・iOS 拡張込みビルド exit 0」）。
- task-1 stage-1 pass、task-4 stage-1（persona-reviewer）pass ＋ stage-2（Claude reviewer）pass（spawn→ready→send 順序・phantom polling 抑止・model→kind 衝突解消・二重 spawn なしを両者が実コードで確認）。
- task-6 stage-1 needs_changes → HIGH は task-1 の phantom polling seam（task-4 領域）と裁定、task-6 自身のスコープ（Widget 拡張・App Group・SharedSessionStore round-trip）は合格。stage-2（Claude reviewer・独立ビルド再現）が起動時空上書き HIGH を検出、PM 修正後 stage-2 へ確認依頼。
- phase-4: XCUITest/スクリーンショットテストを wave-4 UI 変更へ整合（コミット `ca6cece`/`67449e0`）。

**本蒸留作業ではテスト・ビルドの再実行は行っていない**（上記は run 内の記録の要約。実施記録の出典は decision-log.md および `git log`）。

## 積み残し・実機確認事項

- **App Group ポータル登録待ち**: Apple Developer portal で App ID `com.phlox.mobile.PhloxMobile` / `com.phlox.mobile.PhloxMobile.PhloxWidget` の双方に `group.com.phlox.mobile` を登録しないと、実機向けコード署名が `application-groups` entitlement 不一致で失敗する。**本 run では実機ビルドを実施していない**（→ [adr/0009](../adr/0009-widgetkit-app-group-session-status.md)）。
- ウィジェットの実機表示（レイアウト・`accessoryRectangular`/`systemSmall` の見え方）は上記ブロッカーのため未確認。
- ドラフト compose 送信失敗時（spawn/waitUntilReady 失敗）の UX（送信テキスト・添付が既にクリアされた状態での再入力）は許容トレードオフとして未改善（→ adr/0008）。
- 429（レート制限カウントダウン）の compose 側再導入は wave-2 で `SpawnViewModel` 依存として削除されたまま、本 run でも未再実装。
- `Features/SessionsOverview`（俯瞰 grid/single）はソース削除せずデッドコードとして残置。再利用または物理削除の要否は follow-up。
- wave-1 task-5 実装済みの Face ID を含む認証まわりの実機確認は wave-2 worklog（[delivery/0001](0001-mobile-ui-overhaul-wave2-worklog.md)）から継続の積み残し。
