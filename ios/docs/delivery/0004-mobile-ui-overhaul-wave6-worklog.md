---
status: completed
last-verified: 2026-07-16
---

# 0004: モバイル UI 刷新 wave-6（実機検証の追修正6件）作業ログ

> **このファイルの役割**: この run（base = `task/mobile-chat-live`＝wave-5 統合ブランチ・未マージ、作業 worktree 同一、wave-6 = wave-5 実機検証で出た6件の追修正）で何をしたかの記録・状態スナップショット。
> **書かないもの**: 恒久仕様・現行構成（→ 生成した adr/architecture の各リンク先）。

## 依頼内容（6件・wave-5 実機検証由来）

wave-5（[delivery/0003](0003-mobile-ui-overhaul-wave5-worklog.md)）を実機検証した結果出た追修正6件: ①入力欄のコンパクトなピル型再デザイン（左＋・中央プレースホルダ・右マイク、送信/停止を同一スロット化） ②チャット画面のヘッダーカード削除 ③音声入力のクラッシュ修正 ④フォーカス時のオレンジ枠廃止＋落ち着いた配色 ⑤モデルセレクタチップ・スロットの維持（条件表示） ⑥アプリ表示名を「Phlox」に復帰（`PhloxMobile` へのデグレ修正）。①②④⑤は task-1、③は task-2、⑥は PM 直接（共有面 `project.yml`）で実施した。

base に wave-5 統合ブランチ（`task/mobile-chat-live`、未マージ）を採ったのは、6件すべてが wave-5 で導入したコードの実機検証フィードバックであるため（decision-log wave-6 フェーズ0/1）。

## 何をしたか（task-1・task-2・PM 直接）

- **task-1**（`ios/Packages/PhloxKit/Sources/DesignSystemIOS/Molecules/DSInputBar.swift`／`ios/Packages/PhloxKit/Sources/Features/SessionDetail/SessionDetailView.swift`）: 入力欄をカード型からコンパクトなピル型（`Capsule()`）へ再デザイン。写真添付・テキストフィールド・モデルセレクタスロット・マイク・送信/停止アクションを1行の `pillRow` に統合し、`DSInputBarActionState`（`.none`/`.send(isEnabled:)`/`.stop`）で送信と停止を同一スロットに排他表示、`SessionDetailView` の別置き停止ボタンを廃止した。フォーカス時のオレンジ強調枠（`DSColor.accent`）を廃止し、常に中立色（`DSColor.campCardBorder`）固定にした。チャット画面のヘッダーカード（`SessionDetailView.headerCard`＝エージェントバッジ・ステータスチップ・メタ行）を削除した（→ [ADR 0016](../adr/0016-input-bar-compact-pill-redesign.md)）。
  - **初回 status=blocked**（PM の契約指示ミス）: `providesInlineModelSelectorSlot = false` を指示したところ、allowed_paths 外の凍結テスト（`Task3AcceptanceTests`／`Task3KeyboardDismissTests`）とプレースホルダ契約（`SessionDetailCopy.inputPlaceholder`）に衝突。凍結テストは不変のままスロットを `= true` へ復元し、プレースホルダは既存契約文言（「回答を入力…」）を維持することで是正し、全テスト green にした（decision-log wave-6 フェーズ2/3/4）。
- **task-2**（`ios/Packages/PhloxKit/Sources/DesignSystemIOS/Molecules/DSVoiceInputController.swift`）: 音声入力クラッシュの根本修正。simulator 再現で2機序を特定した — (1) TCC 完了ブロック（`SFSpeechRecognizer.requestAuthorization`/`AVAudioApplication.requestRecordPermission`）のメインスレッド期待違反による libdispatch アサーション `SIGTRAP`、(2) `installTap` への不正フォーマットによる Objective-C `NSException` `SIGABRT`。いずれも Swift の `do/catch(Error)` では捕捉不能な種類のクラッシュ。危険 API 呼び出し前の前提検証（`DSVoiceRecognitionSetupState`／`DSVoiceAudioFormatValidator`、活性化後の `inputFormat(forBus: 0)` を検証）、TCC コールバックを `nonisolated static` 関数越しに呼ぶスレッド境界の是正、安全なオーディオ設定（`.record`/`.default`・`.duckOthers` 除去）、simulator ガード（`#if targetEnvironment(simulator)` で実機経路は温存）で根絶した（→ [ADR 0015](../adr/0015-voice-input-crash-hardening.md)）。
- **PM 直接**（`ios/App/Info.plist`／`ios/project.yml`）: アプリ表示名を `CFBundleDisplayName: Phlox` に設定（`PhloxMobile` へのデグレを修正）。共有面（project.yml）のため PM が専有実施。

## 生成・更新した永続ドキュメント

- [ios/docs/adr/0015-voice-input-crash-hardening.md](../adr/0015-voice-input-crash-hardening.md)（音声入力クラッシュ2機序の特定と、危険 API 呼び出し前ガード＋nonisolated ブリッジによる根絶）
- [ios/docs/adr/0016-input-bar-compact-pill-redesign.md](../adr/0016-input-bar-compact-pill-redesign.md)（入力欄をカード型からコンパクトなピル型へ再デザインし、送信/停止を同一スロットに統合した決定）
- [ios/docs/architecture/overview.md](../architecture/overview.md)（`DSInputBar` のピル型構成・送信/停止スロット・中立フォーカス枠・音声入力の前提検証を反映、ヘッダーカード削除を反映）
- [ios/docs/adr/README.md](../adr/README.md)・[ios/docs/delivery/README.md](README.md)（索引追記）

## 検証結果（run 内で実施・decision-log.md の記録に基づく）

- task-1 stage-1 pass（350/0）・stage-2 pass（403+350/0、wave-5 XCUITest 5/5 も stage-2 で実走 pass）。
- task-2 stage-1 pass・stage-2 pass（Apple ヘッダの記述とメインスレッド機序の妥当性を突き合わせて裏取り済み）。
- 独立性: 実装＝Codex（ヘッドレス）×レビュー＝Claude（persona-reviewer＋reviewer、Sonnet）のクロスツール。両タスクとも MUST/HIGH 0。
- **統合検証 = pass**: 全タスクを統合ブランチへマージ後 `.claude/verify.sh` 実走で `verify: OK`、wave-5 XCUITest（`Wave5RegressionUITests`）5/5 pass の再実走を確認。実機ビルド・インストール済み。
- task-1・task-2 を `done` に確定。

**本蒸留作業ではテスト・ビルドの再実行は行っていない**（上記は run 内の記録の要約。実施記録の出典は decision-log.md）。

## 積み残し・実機確認事項

- **音声入力の実機実録音は未検証**: `swift test` は macOS ホスト実行のため iOS 専用 `SFSpeechRecognizer` 系コードはコンパイル対象外（確認できるのは iOS シミュレータビルドの通過まで）。今回の機序特定・修正の妥当性は simulator 再現とユニットテスト、Apple ヘッダとの突き合わせに基づくもので、実機での再発有無は次回実機検証で裏取りが必要。
- **ピル型 UI の実機体感は未検証**（タップ領域の実感・視覚バランス）。
- wave-5 worklog（[delivery/0003](0003-mobile-ui-overhaul-wave5-worklog.md)）の積み残し（ライブアクティビティのロック画面実配信・App Group ポータル登録待ち・`Features/SessionsOverview` デッドコード残置等）は本 run のスコープ外で継続。
