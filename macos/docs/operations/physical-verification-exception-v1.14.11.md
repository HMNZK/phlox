# 1.14.11/build57 実機検証の限定例外

2026-11-12、ユーザーは「今回の3成果物だけ省略して公開を承認」と明示した。対象は、ソースOID `0e95aad30367e2abafc0958d96991d8276cc11fb`から作った以下の成果物に限る。前版の承認や別の再ビルドへ流用しない。

| 成果物 | SHA-256 |
|---|---|
| `distribution-candidate/Phlox.dmg` | `f136a3bbbad76417395e7ecc62b597d196fcb61ff82dd26239dfb5d1d1f154b2` |
| `distribution-candidate/Phlox-1.14.11.zip` | `044aa17f4548c5e1b13fdbd1526a26bdd34c642f346b84d727ab35af0ee2482f` |
| `distribution-ios/PhloxMobile-1.0-26.ipa` | `e89221901b6b48668e7d608bdf4f9bb86650a7cd38f98c314a29f3207249afe3` |

必須実機5項目は`not_run`のまま。人による実機観測・合格記録は追加しない。比較用iOS IPAは端末へ導入せず、配布しない。

固定入力の標準品質ゲート、独立レビュー、送信履歴の秘密情報検査、MacのDeveloper ID署名・公証・staple、Sparkle署名、Mac/iOSビルドの来歴と配布物の正本照合は維持する。今回のmain統合だけ`physical-exception-approval.json`と3ハッシュを確認する限定手順を使う。通常の実機記録ゲート自体は変更しない。統合後のGit設定は今回の配布物を参照する通常ゲートへ戻す。

承認票と成果物・検証証跡は元リポジトリの`release-archives/evidence/1.14.11/mac57-ios26/`に保存する。実機固有の問題が残る可能性は、この限定承認の範囲に含まれる。
