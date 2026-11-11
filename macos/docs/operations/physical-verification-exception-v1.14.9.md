# 1.14.9 build55 実機検証の限定例外

2026-11-11、ユーザーは作成済みのMac1.14.9/build55・照合用iOS1.0/build24に限り、実機5項目を再実施せず進めることを「この候補だけ省略して進める」と明示承認した。前版の承認を流用せず、本書の固定配布物だけに適用する。

| 配布物 | SHA-256 |
|---|---|
| distribution-candidate/Phlox.dmg | `5284bba30744f186691e327c95b7d75f6e1b507aa28af19f3dc72abddfdda913` |
| distribution-candidate/Phlox-1.14.9.zip | `eaa6941c0c0227636f287f952d54c7813b0794097dade01b4cf26fd5c3100cf6` |
| distribution-ios/PhloxMobile-1.0-24.ipa | `6aeb64ab7260c1464f364baff9ec721435a1dbf28e1a500e19c2428da16b13a9` |

ビルド起点は`077046a919d4988d43ce79ce579f91365e63324b`。iOS・共有AgentDomain・公開ControlServerに変更はない。比較用iOS24は来歴照合のため作成し、端末へ導入せず配布もしない。

実機5項目は`not_run`とし、必須区分やシナリオ版を変えず、人の観測証言・合格結果も追加しない。Macの署名・app/DMG公証・staple、同じapp由来のZIP、XPC等4検査、Sparkle署名、正本distributionによる来歴・入力・配布物照合は維持する。これらやAIレビューを人の実機確認へ読み替えない。

ユーザーの指示に従い全体品質ゲートは固定入力に対して一度実行し、両統合候補で入力manifest・シナリオ・toolchain・合格記録の一致を検査して再利用する。独立レビューと履歴の秘密情報検査は省略しない。検査不能や入力変更を合格にしない。

この公開作業だけローカルgitflow設定を、入力一致を検査する品質結果再利用アダプターと、上記3ハッシュを確認するdistribution照合へ接続する。製品ゲート・カタログの必須条件は変更しない。終了時は、通常のqualityと、今回の配布物を参照する通常のreleaseへ戻し、設定の実値を確認する。

証拠基準は元リポジトリの`.verification/release-evidence/1.14.9/mac55-ios24/`。承認文は`physical-exception-approval.json`へ保存する。未検証の実機固有の問題が残る可能性は受け入れた範囲であり、次版への例外にはならない。
