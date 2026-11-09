# 1.14.7 実機検証の例外記録

2026-11-09、利用者は今回のリリースに限り、必須実機検証を未実施のまま公開する例外を明示承認した。

`release/verification-scenarios.json` の `physical-session-activity`、`physical-history-follow`、`physical-activity-presentation`、`physical-usage-preferences-refresh`、`physical-newchat-worktree-resume` はいずれも **未実施**。`release/verification-records.json` に合格記録や人間の観測証言を追加しない。

2026-11-09 17:46 JST 以降、AI が CLI で Mac 1.14.7/build 51 と iPhone 1.0/build 20 の署名済み候補を実機へ導入し、プロセス起動と Mac の新しい常駐サービスによるポート待受を確認した。iPhone の既存設定ファイルが更新後も存在することも確認した。根拠は `.verification/release-evidence/1.14.7/mac51-ios20/physical-preflight/` の `mac-install-build51.txt`、`ios-install-build20.json`、`ios-apps-after.json`、`ios-process-build20.json` に保存した。これらは上記5項目の画面操作、接続、アクセシビリティ、復旧動作の合格を意味しない。Computer Use による Phlox 画面操作が承認されず、人間の実機観測結果も得られなかった。

例外の対象は、配布物の入力コミット `f3c3fcb50ab651bb2ba96271dc93417f16e5fb38` から作成した Mac DMG（SHA-256 `7b9b94e2a527aa4baf2e8dba2dcc6df646887bf4cbe34e176ab80ceced2b1a66`）、Sparkle ZIP（`d3137886dd60dff7be2322a46869fac0d30ab4b91db1fe6b66a9a2e24d0bf85c`）、iOS IPA（`07cb9c9130e340f829304f4e14ad00aa89097abe2bd2aa7f5dba98564e0281c3`）を照合する今回の統合候補だけである。配布物を作り直した場合は再判断する。

この統合に限り、リポジトリのローカル Git 設定 `gitflow.releaseCommand` を、例外文書の存在確認と `verification-gate.py distribution` の実行に切り替える。通常の `quality` と署名・公証・配布物の整合性確認は省略しない。旧設定は `.verification/release-evidence/1.14.7/mac51-ios20/physical-preflight/release-command-exception.txt` に保存した。`main` 統合の成否にかかわらず、統合作業を終えたら旧設定を復元し、`git config --local --get gitflow.releaseCommand` に `verification-gate.py release --dmg` が含まれることを確認する。実機でのみ見つかる操作・表示・接続の不具合が公開後に判明するリスクを受け入れた判断であり、次版以降の実機検証要件は変更しない。
