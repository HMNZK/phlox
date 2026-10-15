---
status: accepted
---

# 0200: 下部パネルの開閉を ⌘J にし、「次の対応待ちへ」を ⇧⌘J へ移す

## 決定

- 下部パネルの開閉キーを ⌃` から ⌘J に変える。
- これまで ⌘J だった「次の対応待ちへ」を ⇧⌘J に移す。
- ⌃` を端末より先にメニューへ渡す `IMETerminalView.keyDown` の上書きを消し、Vendor の `keyDown` の `open` 化を元に戻す。Vendor に残す差分は `becomeFirstResponder`・`resignFirstResponder` の `open` 化だけになる。

## 理由

ユーザーは JIS 配列を使っており、⌃` はこの Mac では ⌃@ と表示されて押しにくい。ユーザーは ⌘J を選んだ（2026-10-15）。⌘J は競合の比較資料（`research/competitor-analysis-conductor-superset.md`）でもターミナルの開閉に使われている。「次の対応待ちへ」は J の並びのまま残すと覚え直しが少ない。

⌘ 付きのキーは AppKit が `keyDown` より前にメニューへ渡す。SwiftTerm は `performKeyEquivalent` を上書きしていないので、端末に入力先があっても特別な処理は要らない。

## 結果

- ADR 0196 の「⌃` は端末のキー処理より先に標準メニューへ渡す」と、ADR 0197 の Vendor 差分のうち `keyDown` の分を置き換える。
- ADR 0186 で残した ⌘J（次の対応待ちへ）は ⇧⌘J になる。
- シミュレーターの画面に入力先があるときも、他の通常の ⌘ キーと同じく ⌘J・⇧⌘J は Phlox 側で扱う（`SimulatorKeyRouting`）。
