---
status: accepted
last-verified: 2026-07-27
---

# ADR 0126: `GET /sessions/{id}/output` は要求があれば色つきの端末画面を返す

> **このファイルの役割**: モバイルが Mac と同じ見た目でターミナルを描けるよう、出力エンドポイントへ色つき表現（`format=ansi`）を足した決定と、その wire 形。
> **書かないもの**: モバイル側の描画方法（→ [ios/docs/adr/0034](../../../ios/docs/adr/0034-mobile-terminal-rendered-with-swiftterm.md)）。

## 文脈

`GET /sessions/{id}/output` は `TerminalCoordinator.visibleText()` を返していた。これは SwiftTerm の viewport を**プレーンテキスト化**したもので、色・太字・反転がすべて落ちる。モバイルはこれをそのまま等幅テキストとして並べていたため、「ターミナル画面」ではなく「文字の羅列」に見えていた（ユーザー報告）。

Mac 側はすでに完全なエミュレーションを終えたセル単位の画面を持っている。足りないのは**それを色ごと運ぶ形式**だけである。

## 決定

1. **`format` クエリを足す**（`text` 既定 / `ansi`）。既定は従来とバイト単位で同じ応答で、既存クライアントに影響しない。
2. **`format=ansi` では viewport を SGR 付きテキストへ書き出して返す**（`AnsiScreenEncoder`）。属性が変わる境界でだけエスケープを挿入し、行末の「既定属性の空白」は落とす。背景色・反転・下線の付いた空白は見た目に出るので残す。
3. **応答に `cols`（Mac の端末幅）を添える**。本文は Mac の桁数で折り返し済みなので、受け手が狭く描くと二重に折り返して崩れる。受け手はこの桁数を守る必要がある。
4. **端末を持たないセッション（構造化 appServer）は従来のプレーンテキストへ落とす**。`format` フィールドが付かないことで、クライアントは落ちたことを見分けられる。

## 棄却案

- **常に ANSI も一緒に返す**: クエリを足さずに済むが、色を使わないクライアントにも毎ポーリングで数倍のペイロードを払わせる。
- **PTY の生バイト列をリングバッファで配信する**: 「本物の端末データ」ではあるが、途中から再生すると受け手のエミュレータ状態（カーソル位置・alt screen）が Mac と一致せず化ける。Mac 側でエミュレーション済みの**画面**を送るほうが決定論的。
- **SwiftTerm の内部 `Attribute.toSgr()` を public にする**: Vendor への変更はスコープ外。呼び出し側で同じ SGR を組める。
- **`mode=ansi` として `OutputMode` に足す**: mode（画面 / スクロールバック）と format（色の有無）は直交する軸で、混ぜると両方を指定できなくなる。

## 結果

- `AnsiScreenEncoder` 7 件・ハンドラ 3 件・ルーティング 3 件のテストを追加し、`TerminalUI` 57 / `AppBootstrap` 151 / `SessionFeature` 407 / `DashboardFeature` 1449 が green。
- **scrollback は含まない**（viewport のみ）。`Buffer.linesTop` が SwiftTerm 内部で非公開のため、スクロールバックの範囲を外から特定できない。加えてエージェントセッションは spawn 前に `disableScrollback()` を通るので、そもそも viewport より上に履歴が無い。
