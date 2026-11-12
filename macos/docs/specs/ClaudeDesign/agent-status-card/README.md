# エージェント状態カードのデザイン見本

ユーザーが Claude Design で作成した見本を、2026-11-07 に `/Users/ryosuke/Downloads/phlox-agent-status-card/` から内容を変更せず取り込んだ。2026-11-09 の利用者指示で、HTML の作業状態と実行中の時間表示を改訂した。2026-11-11 の表示改訂（[要件](../../agent-status-card.md#2026-11-11-改訂-カードの担当と編集中の表示)）で、`boards/04-Done.html` の見出しに変更行数を、`boards/card.css` に変更行数の配色・作業行のホバー・差分欄の余白・点描の虹色を追加した。

- [一覧](index.html): 閲覧用の10画面。
- [部品・全状態の対応表](boards/10-Anatomy.html): 寸法・色・状態・VoiceOverの文言。
- [PDF](pdf/phlox-agent-status-card.pdf): 初回受領時の全画面の書き出し。11月9日・11日の表示変更はHTMLを参照する。
- `source/`: 編集用の元データ。

`source/*.dc.html` が参照する `support.js` は、受領データには含まれていない。閲覧には `index.html` と `boards/` を使う。元データのスクリプトは実行していない。HTMLにはGoogle Fontsへの外部参照があり、オフライン時は指定されたシステムフォントにフォールバックする。 `source/canvas.json`（編集用のキャンバス設定）は、統合ゲートがコードの JSON として扱うためリポジトリに入れていない。原本は受領元の `~/Downloads/phlox-agent-status-card/source/` にある。

アプリ全体の再設計案は採用せず、この見本のチャット内カードだけを実装する（要件D18）。
