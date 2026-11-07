# エージェント状態カードのデザイン見本

ユーザーが Claude Design で作成した見本を、2026-11-07 に `/Users/ryosuke/Downloads/phlox-agent-status-card/` から内容を変更せず取り込んだ。

- [一覧](index.html): 閲覧用の10画面。
- [部品・全状態の対応表](boards/10-Anatomy.html): 寸法・色・状態・VoiceOverの文言。
- [PDF](pdf/phlox-agent-status-card.pdf): 全画面の書き出し。
- `source/`: 編集用の元データ。

`source/*.dc.html` が参照する `support.js` は、受領データには含まれていない。閲覧には `index.html` と `boards/` を使う。元データのスクリプトは実行していない。HTMLにはGoogle Fontsへの外部参照があり、オフライン時は指定されたシステムフォントにフォールバックする。

アプリ全体の再設計案は採用せず、この見本のチャット内カードだけを実装する（要件D18）。
