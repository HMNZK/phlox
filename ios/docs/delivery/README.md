---
status: active        # active | completed | superseded | archived
last-verified: 2026-10-19
---

# delivery/

**役割（ここにしか書かない）**: フェーズ作業ログ・引き継ぎ・変更履歴（過去の経緯・状態スナップショット）

**書かないもの**: 恒久仕様（→ specs/・architecture/）

**Diátaxis**: Status

**命名**: 小文字 kebab-case・ASCII・`.md`（索引のみ `README.md`）。順序ありは `NNNN-kebab.md`。

## 他ディレクトリにある iOS の作業記録

- [新規チャットの写真添付時の停止](../../../macos/docs/delivery/0213-mobile-photo-freeze.md) … 写真選択と入力欄フォーカスの調査・修正・実機確認の記録

## 現在あるファイル
- `delivery/0001-mobile-ui-overhaul-wave2-worklog.md` … モバイル UI 刷新 wave-2（8タスク）の作業ログ
- `delivery/0002-mobile-ui-overhaul-wave4-worklog.md` … モバイル UI 刷新 wave-4（6タスク）の作業ログ
- `delivery/0003-mobile-ui-overhaul-wave5-worklog.md` … モバイル UI 刷新 wave-5（5タスク）の作業ログ
- `delivery/0004-mobile-ui-overhaul-wave6-worklog.md` … モバイル UI 刷新 wave-6（実機検証の追修正6件）の作業ログ
- `delivery/0005-mobile-ui-overhaul-wave7-worklog.md` … モバイル UI 刷新 wave-7（入力欄整理・顔認証既定オフ）の作業ログ
- `delivery/0006-mobile-ui-overhaul-wave8-worklog.md` … モバイル UI 刷新 wave-8（QR接続直後オフラインバグ・チャット画像添付表示）の作業ログ
- `delivery/0007-mobile-ui-overhaul-wave9-worklog.md` … モバイル UI 刷新 wave-9（接続中オーバーレイ・添付バッジ分離）の作業ログ
- `delivery/0008-chat-transcript-perf-worklog.md` … 会話本文の表示性能改善の作業ログ
- `delivery/0009-thinking-recap-wiring-worklog.md` … Thinking要約表示の配線作業ログ
- `delivery/0010-ask-user-question-worklog.md` … AskUserQuestion 対応（iOS ミラー実装）の作業ログ
- `delivery/0011-draft-compose-send-button-fix-worklog.md` … 下書き送信ボタンの修正記録
- `delivery/0012-mobile-multiline-send-fix-worklog.md` … 複数行入力の送信操作修正記録
- `delivery/0013-inline-image-attachments-worklog.md` … 添付画像の番号付けと本文への `[Image #N]` 埋め込み（iOS 18 化）の作業ログ
- `delivery/0014-ios-single-toolcall-row-worklog.md` … 単独ツールコールを「ツール実行 ×1」の1行集約行に畳む変更の作業ログ
- `delivery/0015-mobile-reliability-fixes-worklog.md` … モバイル信頼性修正5件（接続中表示・入力欄消失・サブエージェント固まり・質問カード排他・モデル選択の安定化）の作業ログ
- `delivery/0016-session-view-ux-worklog.md` … セッション表示 UX（最下部から開く・本文の折り返しと表の横スクロール・端スワイプで戻る）の作業ログ
- `delivery/0017-tool-call-collapse-threshold-worklog.md` … ツールコール件数と折りたたみ閾値の分離の作業ログ
- `delivery/0018-ios-session-project-assign-worklog.md` … iOS で作ったセッションが macOS の「その他」に落ちる問題（spawn への projectId 伝搬）の作業ログ
- `delivery/0019-mobile-chat-parity-worklog.md` … デスクトップのチャット表示刷新（コードカード・ツール実行の見出し・diff コードビュー）をモバイルへ適用した作業ログ
- `delivery/0020-ios-redesign-plan.md` … iOS アプリを再設計の見本（2026-10 の Claude Design）どおりに作り直す実装計画
- `delivery/0021-ios-redesign-stage1-worklog.md` … 再設計の段階 1（土台の部品と、廃止する機能の削除）の作業記録
- `delivery/0022-ios-redesign-stage2-worklog.md` … 再設計の段階 2（API の配線とサブエージェント詳細の廃止）の作業記録
- `delivery/0023-ios-redesign-stage3-worklog.md` … 再設計の段階 3 前半（下部ナビゲーション）の作業記録
- `delivery/0024-ios-redesign-stage4-worklog.md` … 再設計の段階 4（入力欄・セッション設定・使用量リング）の作業記録
- `delivery/0025-ios-redesign-stage5-worklog.md` … 再設計の段階 5（新規チャット画面）の作業記録
- `delivery/0026-ios-redesign-stage6-worklog.md` … 再設計の段階 6a〜6c（セッション画面・会話表示・承認と質問カード）の作業記録
- `delivery/0027-ios-redesign-stage7-worklog.md` … 再設計の段階7（ウィジェット・Live Activity・Dynamic Island と通知からの遷移）の作業記録
- `delivery/0028-ios-redesign-stage8-worklog.md` … 再設計の段階8a（起動・接続・設定・エラー文言と描画場面の追加）の作業記録
- `delivery/0029-ios-redesign-8b-attachments.md` … 段階8bの添付表示・受け入れ担当記録
- `delivery/0029-ios-redesign-8b-cards.md` … 段階8bの承認・質問カード担当記録
- `delivery/0029-ios-redesign-8b-chat.md` … 段階8bの会話画面担当記録
- `delivery/0029-ios-redesign-8b-composer.md` … 段階8bの入力欄・使用量担当記録
- `delivery/0029-ios-redesign-8b-delete-retry.md` … 段階8bの削除失敗・再試行担当記録
- `delivery/0029-ios-redesign-8b-fixtures.md` … 段階8bの撮影fixture担当記録
- `delivery/0029-ios-redesign-8b-gate-accessibility.md` … 段階8bの起動ゲートアクセシビリティ記録
- `delivery/0029-ios-redesign-8b-integration.md` … 段階8bの統合・契約確認記録
- `delivery/0029-ios-redesign-8b-list.md` … 段階8bの一覧画面担当記録
- `delivery/0029-ios-redesign-8b-pair.md` … 段階8bのペアリング画面担当記録
- `delivery/0029-ios-redesign-stage8b-worklog.md` … 再設計の段階8b（見本との差の修正・まとめの検証と引継ぎ）の作業記録。担当別の記録も同じ番号で配置する
- `delivery/0030-ios-newchat-progress-worklog.md` … 新規チャットの作成待ち表示と、送信中の下書き保護の作業記録
- `delivery/0031-ios-accessibility-snapshot-worklog.md` … 最大文字サイズへの追従、実ポップアップの検証、スクロール診断と未確認範囲の作業記録
- `delivery/0032-ios-error-catalog-verification.md` … エラーカタログの実装・表示経路照合記録
- `delivery/0032-ios-remaining-acceptance-worklog.md` … 残存受け入れ条件と追加実行の作業ログ
- `delivery/0033-ios-cursor-vector-probe.md` … Cursorロゴ描画の比較probe記録
- `delivery/0033-ios-offline-accessory-worklog.md` … オフライン案内のnative tab表示検証ログ
- `delivery/0034-composer-ime-placeholder.md` … 日本語変換中に入力欄の placeholder が未確定文字列と重なる問題の修正・検証記録（dev 統合時の macOS 合成クリックテスト削除と依存固定の経緯を含む）
- `delivery/0034-ios-root-transition-verification.md` … Root遷移と実操作検証の作業ログ
- `delivery/0035-ios-real-biometric-gate-probe.md` … Face ID実権限経路probe記録
- `delivery/0036-composer-ime-submission.md` … 日本語変換中の本文を含めて送信する入力欄修正の問題定義と検証記録
- `delivery/0036-mobile-skill-suggestions.md` … スマホ入力欄のスキル候補（取得・選択・Codex native送信）の作業記録。恒久仕様は macos/docs/specs/mobile-skill-suggestions.md
