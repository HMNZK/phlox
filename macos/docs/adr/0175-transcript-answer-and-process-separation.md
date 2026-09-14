---
status: accepted
last-verified: 2026-09-14
---

# ADR 0175: 回答本文と処理詳細を意味別に分けて表示する

> **このファイルの役割**: 回答、思考、処理、エラーが同じ強さで並ぶ transcript を、読み手が回答を先に読める形へ分けた理由を残す。
> **書かないもの**: カードの枠・コード表示・時刻や件数を落とす決定（→ [ADR 0147](0147-chat-code-card-and-header-dedup.md)）。

## 文脈

回答本文と英語の処理見出し・コマンドが競合し、Markdown の装飾記号が本文として見える経路があった。
コード中の記号は保持しつつ、思考や処理の詳細は必要なときだけ読める必要がある。

## 決定

- `TranscriptItemPresentation` を回答・思考・コマンド・差分・タスク・エラーの表示意味の共通入口にする。
- 回答は primary 色の Markdown として常時表示する。思考本文は secondary 色、処理詳細は既定で閉じ、エラーは error 色にする。
- 回答 Markdown だけが `prepare`、要約、フェンス分割を通る。コード、コマンド出力、コピー原文には整形を流さず、記号と末尾空行を保持する。
- Markdown の表セルは固定色ではなく渡された本文色を使う。

## 結果

- [ADR 0147](0147-chat-code-card-and-header-dedup.md) の Reasoning 限定「見出しと本文が同一なら 1 行にする」を部分置換する。コードカードとコマンドカードの器、重複 chrome の削減は不変である。
- 受け入れテストには `AcceptanceTranscriptMarkdownPresentationTests` が登録され、回答 Markdown の整形境界と本文色を検査する。実画面の確認はテストとは別に記録した。
