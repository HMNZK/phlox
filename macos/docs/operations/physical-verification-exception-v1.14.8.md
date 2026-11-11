# 1.14.8 build54 実機検証の限定例外

2026-11-11、ユーザーは「この候補だけ例外を認めて進める」と明示承認した。対象は Mac 1.14.8/build54 と照合用 iOS 1.0/build23 の、下記ハッシュで固定した候補だけである。再生成した配布物や次版には適用しない。

| 対象 | SHA-256 |
|---|---|
| Mac DMG | `a081f1eb4c294a7f11f0497e983e2281684ec59fb43af5b1c99752207dcefe85` |
| Sparkle ZIP | `18a564b673b0dfe5de387efafbc2373dc8c9bdf529fe47f875279212bf8a8cf2` |
| iOS IPA | `cbafd36a0ac3a3e1431487c298f856768675c07a71feb74c1531b4439cfe222a` |

ビルド起点は `01b35c25dbbf6e39112e5380f7e768578bb9f792`。main `820a110f` から dev `795a9feb` への差分では、iOS・共有 AgentDomain・公開 ControlServer の変更は0件だった。今回の本文取得修正を、スマホの表示・ジェスチャー・背景動作5項目の一律再実施へ広げる技術的根拠は確認できず、ユーザーへ範囲を明示して判断を得た。

必須実機シナリオ5件（`physical-session-activity`、`physical-history-follow`、`physical-activity-presentation`、`physical-usage-preferences-refresh`、`physical-newchat-worktree-resume`）は **未実施** とする。カタログの必須区分・要求・版を変更せず、`release/verification-records.json` の `devices` と `executions` に合格や人の観測証言を追加しない。

AIは Mac の画面と常駐サービスを54へ切り替え、既存10会話の復元、新規の専用会話での送信と `QA54_OK` の応答を確認した。iPhoneは1.0/build23の直接導入・別照会による版確認・起動が成功した。iPhoneの画面操作はミラーリングの本人認証待ちで未実施であり、これらを5件の合格へ読み替えない。

証拠基準は元リポジトリの `.verification/release-evidence/1.14.8/mac54-ios23/`。新候補の署名・アプリ/DMG公証・staple、同じアプリからの最終ZIP、XPC等4検査、Sparkle署名、正本 `distribution` による来歴・入力・実効設定・公開鍵・配布物照合は成功済み。dev統合の全体品質ゲートと秘密情報検査も成功し、mainの最終候補でも通常の全体検査と秘密情報検査を実行する。

この統合だけ、ローカル `gitflow.releaseCommand` を、上記3ハッシュと本書の存在確認を先行させた `verification-gate.py distribution` へ限定する。既存の版・ノート・フィード・stapler検査を維持し、共通マージツールと製品ゲートのコードは変更しない。通常設定と限定設定は証拠基準の `exception-20261111/` に保存する。main統合の成否にかかわらず、統合作業の終了後に通常の `verification-gate.py release --dmg` を呼ぶ設定へ復元し、実値を照合する。

これは実機でのみ分かる問題が残り得る範囲を受け入れた判断であり、実機確認の成功ではない。main統合・公開の成功も、本書の作成だけでは主張しない。
