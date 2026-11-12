# Phlox 1.14.11

## 対象

Mac 1.14.11/build57。Codexの思考要約を状態カード・会話ログから隠し、通常の進捗報告・作業・最終回答を残す。元の会話データは変更しない。iOS状態カードの開発変更もdevへ統合するが、この公開ではiOSアプリを配布しない。利用者向けの変更は[リリースノート](../../../release/notes-v1.14.11.md)に記す。

## 配布と検証

Macの署名・公証済みDMGと、同じstaple済みアプリから作るSparkle更新ZIPを新規作成する。比較用iOS 1.0/build26のAd Hoc IPAも新規作成し、両ビルドの入力・来歴・ハッシュを元リポジトリの`release-archives/evidence/1.14.11/mac57-ios26/`に保存する。`.verification/`には作業後に削除できる一時物だけを置く。

標準品質ゲート、独立レビュー、配布物と更新フィードの照合を完了してからdev・mainへ共通マージツールで統合する。実機5項目は新しい成果物で記録し、未実施の場合は`not_run`のまま保持する。前版1.14.10の限定承認は今回へ流用しない。

## 固定候補の実測結果

ソースOIDは`0e95aad30367e2abafc0958d96991d8276cc11fb`。標準品質ゲートはmacOS全19パッケージ、iOS lint・単体・ビルド、必須fake E2Eを通過した。MacアプリとDMGはDeveloper ID署名・公証・staple済みで、同じアプリからSparkle ZIPを作成した。比較用iOS IPAは新規にAd Hoc署名しており、実機への導入・操作はまだしていない。

| 成果物 | SHA-256 |
|---|---|
| `distribution-candidate/Phlox.dmg` | `f136a3bbbad76417395e7ecc62b597d196fcb61ff82dd26239dfb5d1d1f154b2` |
| `distribution-candidate/Phlox-1.14.11.zip` | `044aa17f4548c5e1b13fdbd1526a26bdd34c642f346b84d727ab35af0ee2482f` |
| `distribution-ios/PhloxMobile-1.0-26.ipa` | `e89221901b6b48668e7d608bdf4f9bb86650a7cd38f98c314a29f3207249afe3` |

実機5項目は`not_run`。配布物・来歴・更新フィードの最終照合結果と公開状態は、実行後に追記する。
