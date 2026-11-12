# 1.14.10 build56 実機検証の限定例外

2026-11-12、ユーザーは作成済みのMac1.14.10/build56・照合用iOS1.0/build25に限り、実機5項目を省略して公開することを「今回の固定配布物だけ省略して公開する」と明示承認した。前版の承認を流用せず、以下の固定配布物だけへ適用する。

| 配布物 | SHA-256 |
|---|---|
| distribution-candidate/Phlox.dmg | `20b0839ac4443b8e29e7fe11d8058ce353eae9c6ef20595d3b726280507d5d6e` |
| distribution-candidate/Phlox-1.14.10.zip | `7ac1b1336ba449e2c3f9ae76cb6c4ad822c07517a2bf80e6eabb419e157267a3` |
| distribution-ios/PhloxMobile-1.0-25.ipa | `fa7e218af2eac0cef9cfdaedab242f0a6e0d4be57979781425c09312b83b0ad7` |

ビルド起点は`ae73a5b3069b3c00bc349d229261cd930607a1ce`。iOSは比較用来歴を採取しただけで、端末へ導入せず配布しない。

必須実機5項目は`not_run`のまま。シナリオの必須区分・版を変更せず、人の観測証言や合格結果を追加しない。Macの署名・app/DMG公証・staple・Gatekeeper受理、XPC等の署名4検査、Sparkle署名、正本distributionによる入力・来歴・配布物照合、独立レビュー、統合・送信履歴の秘密情報検査は維持する。

標準qualityは固定入力で成功した。同じ入力manifest・シナリオ・toolchain・合格記録が一致する場合だけ照合して再利用し、全体検査を重複実行しない。不一致・検査不能は失敗とする。

この公開作業だけローカルgitflow設定を、上記3ハッシュと承認票を要求するdistribution照合へ接続する。製品ゲート・カタログ自体は変更しない。終了時に通常のqualityと、今回の配布物を参照して実機記録を要求する通常releaseへ戻し、実値を照合する。

証拠基準は元リポジトリの`.verification/release-evidence/1.14.10/mac56-ios25/`。承認票は`physical-exception-approval.json`。未検証の実機固有の問題が残る可能性を受け入れた範囲であり、次版や別成果物への例外にはならない。
