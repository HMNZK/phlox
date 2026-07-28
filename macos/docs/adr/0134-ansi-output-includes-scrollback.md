---
status: accepted
last-verified: 2026-07-27
---

# ADR 0134: `format=ansi` はスクロールバックを含むバッファ全体を返す

> **このファイルの役割**: 出力エンドポイントの色つき応答から「Mac の viewport だけ」という制限を外した決定と、その上限の置き方。
> **書かないもの**: 受け手（モバイル）がそれをどう描いてスクロールさせるか（→ [ios/docs/adr/0039](../../../ios/docs/adr/0039-mobile-terminal-is-styled-text-not-an-emulator.md)）。

## 文脈

[ADR 0126](0126-output-endpoint-serves-ansi-screen.md) は `format=ansi` を viewport 限定にした。理由は「`Buffer.linesTop` が SwiftTerm 内部で非公開でスクロールバックの範囲を外から特定できない」ことと、「エージェントセッションは spawn 前に `disableScrollback()` を通るので viewport より上に履歴が無い」ことだった。

後者はもう成り立たない。`ScrollbackPolicy` の既定は `.keep` で、`.disableBeforeSpawn` を使うエージェントは現在1つも無い（TUI 側のゴースト再発に備えた退避路として残っているだけ）。つまり Mac 側には SwiftTerm 既定の 500 行の履歴が実際に積もっている。

その結果、モバイルは **Mac に今映っている画面しか持てず、自分では1行も遡れなかった**。ユーザー報告は「スクロールできません」。画面に収まる分しか届いていないのだから、受け手をどう直しても遡れない。

## 決定

1. **`AnsiScreenEncoder.encode` はスクロールバックを含むバッファ全体を書き出す**。`0..<terminal.rows`（viewport の行番号）ではなく、スクロール不変の行番号で `buffer.linesTop ..< buffer.linesTop + buffer.lines.count` を走査する。
2. **範囲は Vendor へ `Terminal.scrollInvariantRowRange` を足して公開する**。`getScrollInvariantLine(row:)` は既に public だが、渡してよい行番号の範囲を外から知る術が無かった。追加したのは既存の内部値を露出する 3 行の computed property のみ。
3. **行数に上限 `defaultMaxRows = 4000` を置き、超えたら古い側から落とす**。既定スクロールバック 500 行では届かないが、設定が変われば転送量と受け手の描画コストが青天井になる。
4. **先頭と末尾の空行は落とす**。バッファは未使用行を空行として持っており、そのまま送ると受け手が大量の空行を描く。
5. **行の読み取り幅は `min(terminal.cols, line.count)`**。桁数を変えた後のスクロールバックは行ごとに長さが違い、`cols` を信じて読むと範囲外になる。
6. **`format=text`（プレーンテキスト）は viewport 限定のまま**。`visibleText()` の意味を変えると Mac 内の既存利用（テスト・ダンプ）まで巻き込む。色つき経路だけを直す。

## 棄却案

- **`mode=scrollback` を実装して使い分ける**: 「履歴が要るかどうか」をクライアントに選ばせる形は一見きれいだが、受け手が独立にスクロールしたい場面は常にあり、選択肢を足すだけで実際には常に片方しか使われない。
- **差分配信（前回送った行以降だけ返す）**: 転送量は減るが、受け手が状態を持つことになり、取りこぼしたときに復旧できない。500 行の全量は数十 KB で、ポーリング間隔に対して十分軽い。
- **SwiftTerm の `buffer` を public 化する**: 露出が大きすぎる。必要なのは行番号の範囲だけ。

## 結果

- `AnsiScreenEncoderTests` に「画面から流れ去った行も書き出す」「上限を超えた分は古い側から落とす」の 2 件を追加し、`TerminalUI` の当該スイート 9 件が green。
- Vendor 差分は `Terminal.scrollInvariantRowRange` の追加のみ（SwiftTerm 本体の挙動は変えない）。
- `.disableBeforeSpawn` のエージェントでは履歴が積もらないため、この決定を入れても遡れる行は増えない。現状そのポリシーを使うエージェントは無い。
