---
status: completed
last-verified: 2026-07-15
---

# 0003: モバイル UI 刷新 wave-5（5タスク）作業ログ

> **このファイルの役割**: この run（base = `task/mobile-projects-ui`＝wave-4、作業 worktree `task/mobile-chat-live`、wave-5 task-1〜task-5）で何をしたかの記録・状態スナップショット。
> **書かないもの**: 恒久仕様・現行構成（→ 生成した adr/architecture の各リンク先）。

## 依頼内容（5項目・バグ2件を優先）

①セッション詳細の右上メニュー（「モデル変更」「名前変更」）が連続タップで開かなくなるバグの修正（task-3） ②セッション一覧（Projects）上部に空白ができるバグの修正（task-4） ③チャット入力欄のカード型再デザイン＋mic 音声入力（branch は表示のみ、Session モデル/API 不変）（task-1） ④reasoning／ツールコール（command/fileChange）行のトグル化（デフォルト折りたたみ）（task-2） ⑤セッション状態変化をロック画面へ自動表示するライブアクティビティ（push 駆動、iOS ActivityKit + macOS APNs）の追加（task-5）。

base に wave-4（`task/mobile-projects-ui`）を採ったのは、バグ2件が wave-4 コードのバグであり、機能追加も wave-4 の上に載るため（decision-log wave-5 フェーズ0/1）。wave-4 は実機検証中のため、別 worktree `task/mobile-chat-live` に隔離して作業した。

## 何をしたか（task-1〜task-5）

- **task-3**（`SessionDetailView.swift`/`SessionDetailViewModel.swift`）: 右上メニューの presentation 取りこぼしバグを修正。`.sheet` を `.alert` とは別の View 階層へ分離し、`private enum MenuPresentation { case modelPicker, rename }` を単一ソースとして排他管理する構造に変更（→ [ADR 0013](../adr/0013-session-detail-menu-presentation-single-source.md)）。task-3 の完了で task-2（同一ファイル共有のため depends_on）が解放された。
- **task-4**（`DSNavigationChrome.swift`）: セッション一覧上部の空白バグを修正。PM 支給の2仮説（appearance 再インストール／ScrollView 位置残り）のうち仮説A（appearance 再インストール）を真因と確認し、`UINavigationBar.appearance()` への再適用をテーマ変更時のみに限定する冪等化で修正（`SessionListView`/`SessionListViewModel` は無改変。→ [ADR 0014](../adr/0014-navigation-chrome-appearance-idempotent-install.md)）。
- **task-1**（`DSInputBar.swift` 新規 `DSVoiceInputController.swift`／`SessionDetailView.swift`／`SessionDetailViewModel.swift`）: 入力欄をカード型（角丸＋上部ドラッグハンドル、下スワイプで閉じる）に再デザインし、`VoiceInputRecognizing` プロトコルで抽象化した音声入力（`DSVoiceInputController`）を追加。branch は `contextLabel`（プロジェクト名で代替表示）として表示のみ実装（→ [ADR 0012](../adr/0012-input-bar-branch-display-only.md)）。stage-1 pass 後、stage-2 で「権限確認中の再入ガード漏れ」「画面クローズ後にマイクが起動する `onDisappear` 未キャンセル」の MUST 2件が見つかり差し戻し修正（decision-log wave-5「task-2/5 マージ・task-1 レビュー」）。task-2 に依存（同一ファイル共有のため逐次実行）。
- **task-2**（`SessionDetailView.swift`/`SessionDetailViewModel.swift`/`DSReasoningText.swift`）: reasoning／command／fileChange 行をデフォルト折りたたみのトグル化。展開状態は `expandedMessageIDs`（`ChatMessage.id` キー）で message 単位に保持し、3秒ポーリングの再取得後も失われない。
- **task-5**（`PhloxCore/LiveActivity/*`／`ios/PhloxWidget/SessionLiveActivity.swift`／`ios/App/Push/LiveActivityPushRegistration.swift`／macOS `APNsNotificationBridge`/`APNsClient`/`DeviceTokenRegistration`）: ライブアクティビティを push 駆動（iOS ActivityKit pushToStart/update + macOS APNs `apns-push-type: liveactivity`）で実装（→ [ADR 0011](../adr/0011-session-live-activity-push-driven.md)）。stage-1 pass 後、stage-2 で「多重起動防止が未実装」「契約4分岐のうち2通り未テスト」の MUST 差し戻しを経て、macOS 側 `actor LiveActivityStartRegistry`（`(sessionId, deviceToken)` 予約）と iOS 側 `LiveActivitySessionIndex` の2層防御を実装し stage-2 再検証 pass。

## 生成・更新した永続ドキュメント

- [ios/docs/adr/0011-session-live-activity-push-driven.md](../adr/0011-session-live-activity-push-driven.md)（ライブアクティビティを push 駆動で実装した決定）
- [ios/docs/adr/0012-input-bar-branch-display-only.md](../adr/0012-input-bar-branch-display-only.md)（入力欄 branch 表示は表示のみとした決定）
- [ios/docs/adr/0013-session-detail-menu-presentation-single-source.md](../adr/0013-session-detail-menu-presentation-single-source.md)（右上メニュー presentation の分離＋enum 単一ソース化）
- [ios/docs/adr/0014-navigation-chrome-appearance-idempotent-install.md](../adr/0014-navigation-chrome-appearance-idempotent-install.md)（nav bar appearance 再適用の冪等化、ADR 0004 と関連）
- [ios/docs/architecture/overview.md](../architecture/overview.md)（ライブアクティビティのセクション新設、`DSInputBar`／`DSVoiceInputController`／`VoiceInputRecognizing`／右上メニュー presentation／メッセージ折りたたみ／`DSNavigationChrome` 冪等化を反映）
- [ios/docs/adr/README.md](../adr/README.md)・[ios/docs/delivery/README.md](README.md)（索引追記。合わせて既存索引に欠けていた ADR 0007〜0010・delivery 0002 の行も補完）

## 検証結果（run 内で実施・decision-log.md の記録に基づく）

- task-2 stage-1 pass（333 tests）、task-5 stage-1 pass（PhloxKit 326 / APNsClient 9 / AppBootstrap 131 green）、task-1 stage-1 pass（343 tests）。
- task-3/task-4 stage-1 = needs_changes（コードは妥当・真因到達だが症状の実挙動を検証する自動テストが無い）。レビュアー自身が提示した pass 条件（フェーズ4 症状 XCUITest＋実機確認）を受理ゲートとして先送りし、コードは統合ブランチへマージ済み。
- task-5 stage-2 = needs_changes（1回目差し戻し。多重起動防止未実装・契約4分岐2通り未テスト）→ 修正後 stage-2 再検証 pass。
- task-1 stage-2 = needs_changes（1回目差し戻し。権限確認中の再入ガード漏れ・`onDisappear` 未キャンセルによる画面クローズ後マイク起動）→ 修正後マージ。
- **フェーズ4 統合検証 = pass**: 全5タスクを run ブランチへマージ後 `.claude/verify.sh` 実走 → PhloxKit ユニット全数＋macOS APNsClient/AppBootstrap＋iOS シミュレータビルド（Widget 拡張含む）green（`verify: OK`、警告は pre-existing のみ）。
- **フェーズ4 症状回帰 XCUITest = 5/5 pass**（`ios/PhloxMobileUITests/Wave5RegressionUITests.swift`、PM が新規著述し実走）: `testListDetailRoundTripKeepsProjectsTitle`（task-4 の受理ゲート）、`testRenameReopensRepeatedly`／`testModelChangeThenRenameBothOpen`（task-3 の受理ゲート）、`testInputCardAffordancesRender`（task-1 の入力欄カード＝ハンドル/音声/添付が実画面に描画されること）、`testDragHandleDismissesKeyboard`（task-1 の「上部を下にスライドで閉じる」＝フォーカス→ハンドル下ドラッグでキーボードが閉じる実挙動）。
- 上記により stage-1 で needs_changes だった task-3/task-4 の pass 条件を満たし、全5タスクを `done` に確定。

**本蒸留作業ではテスト・ビルドの再実行は行っていない**（上記は run 内の記録の要約。実施記録の出典は decision-log.md）。

## 積み残し・実機確認事項

- **ライブアクティビティのロック画面表示・APNs 実配信は未検証**（実機＋実 Mac push が必要。push-to-start の許可プロンプトは実機のみで発火する）。
- 入力欄カードのドラッグ閉じは XCUITest で客観検証済み（`testDragHandleDismissesKeyboard`）。**残る実機/実push 依存の未検証項目**: mic の実録音（ハードウェア音声＋権限付与が必要）、ライブアクティビティのロック画面実配信（wave-5 macOS 送信アプリの起動＋APNs 構成＋解錠済み実機が必要）。シミュレータでのユニット/契約テスト・ビルド・XCUITest・実機インストールまでは green。
- wave-4 worklog（[delivery/0002](0002-mobile-ui-overhaul-wave4-worklog.md)）の積み残し（App Group ポータル登録待ち・ウィジェット実機表示未確認・`Features/SessionsOverview` デッドコード残置等）は本 run でも未解消のまま継続。
