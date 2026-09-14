# ドキュメント蒸留レポート

## 触った文書と変更理由

- `macos/docs/adr/0147-chat-code-card-and-header-dedup.md`: 回答・思考の規則だけを ADR 0175 へ部分置換したことを追記。
- `macos/docs/adr/0046-composer-default-height-compact-revert.md`: UX-03 の入力先表示は既存の高さ方針を変えないことを追記。
- `macos/docs/adr/0121-agent-management-console.md`: UX-10 のエージェント別権限説明と反映時期を追記。
- `macos/docs/adr/0174-terminal-mount-ownership-prevents-blank-after-view-mode-switch.md`: run worklog へのリンクを追加。
- `macos/docs/adr/0024-restore-gate-and-commands-reactivity.md`: 復元中の明示削除を完了後へ繰り越す現行規則を追記。
- `macos/docs/adr/0073-overlay-inset-by-measured-height.md`: セッション名の末尾省略はオーバーレイ余白規則と別であることを追記。
- `macos/docs/architecture/chat-mode-ux-components.md`: 入力先表示と、回答・処理詳細の現行描画を反映。
- `macos/docs/adr/README.md` / `macos/docs/README.md`: ADR 0175 と worklog を索引へ登録。
- `macos/docs/delivery/0036-ui-ux-improvement-backlog-worklog.md`: run の完了範囲と将来のフォローアップ8件を記録。

## 不要と判断した候補

- ADR 0147 全体の supersede: 不要。コードカードと重複 chrome の決定は現行のままで、Reasoning の 1 行規則だけが変わったため、ADR 0175 による部分置換とした。
- ADR 0175 以外の新規 ADR: 不要。今回の残りは既存決定の補足または実装・目視上の追跡項目であり、新しい長期判断ではない。

## 新規追加した文書

- `macos/docs/adr/0175-transcript-answer-and-process-separation.md`
- `macos/docs/delivery/0036-ui-ux-improvement-backlog-worklog.md`

## 未反映で残した点

- フォローアップ8件は仕様・ADRに昇格せず、`delivery/0036` に限定して記録した。合否に影響しない観測または未検証事項であり、修正方針は未決定のためである。
- テストや実画面確認はこのフェーズでは再実行していない。文書中の検証記述は既存テストまたは run 記録の範囲に限定した。

=== REPORT COMPLETE ===
