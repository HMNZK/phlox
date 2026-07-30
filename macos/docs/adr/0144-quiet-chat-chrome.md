---
status: accepted
last-verified: 2026-07-30
---

# ADR 0144: チャットの装飾を落とす（カードのアイコン・ステータスグリフ・アバターの撤去）

> **このファイルの役割**: transcript の各カードから SF Symbol アイコン・実行中スピナー・完了チェック・
> エージェントアバターを外し、ツールコールを半透明グレーにした理由。
> **書かないもの**: ツール実行グループの見出し文言（→ [ADR 0145](0145-tool-group-recap-header.md)）、
> diff の描画（→ [ADR 0146](0146-diff-code-view.md)）、Thinking の orb 表示（→ [ADR 0142](0142-thinking-orb-replaces-shimmer.md)）。

## 文脈

transcript のツールコール・ツール実行グループ・Reasoning・ファイル変更・TaskList は、
すべて共通の `DisclosureCard` で描かれていた。カードは左に SF Symbol（`terminal` 等）、
右端に時刻＋ステータスグリフ（実行中は Core Animation の回転スピナー、完了は緑チェック）を出し、
さらに各行の左には 24pt のエージェントブランドアイコン（`AgentBrandIcon`）が並んでいた。

エージェントは 1 ターンに数十件のツールを呼ぶ。その結果、画面の大半がアイコンとチェックマークで埋まり、
**装飾が本文（何を実行したか）より目立つ**状態になっていた。回転スピナーは常時 1 件以上が回り続ける。

## 決定

**カードの装飾を全面的に落とし、テキストだけで状態を伝える。**

- **`DisclosureCard` から `systemImage` / `accent` / `status` 引数を型ごと削除する。**
  引数を残して呼び出し側で `nil` を渡す形にすると、いつでも復活できてしまい「静かにする」判断が
  コードに残らない。`StatusGlyph` / `DisclosureRunningSpinner` / `DisclosureStatus` も削除した。
- **実行中／完了はサブタイトルとテキスト色だけで表す。** 実行中は `"実行中"`、完了は無表記。
  回転アニメーションが 1 つも走らないため、`reduceMotion` 分岐も不要になった。
- **ツールコール系だけを半透明グレーにする。** `DSColor.chatToolCallText` を新設し、値の契約を
  「アルファ < 1.0」かつ「sRGB の R/G/B の最大差 ≤ 1/255（無彩色）」と定めてテストで固定した。
  実装は各テーマの `textPrimary`（全テーマで grayscale）に不透明度を掛けて導出する。直値を置かないので、
  テーマが増えても無彩色契約が壊れない。
- **色の選択は `DisclosureCardPalette` へ純粋関数として切り出す。** 最初の実装はカード共通の
  `textColor` をタイトルとサブタイトルの両方へ適用し、ツールコール以外（ファイル変更・TaskList）の
  サブタイトルまで secondary → primary へ濃くしていた。独立レビューで検出したこの副作用を、
  タイトル用／サブタイトル用に分けた純粋関数＋4 分岐のテストで再発しない形にした。
- **`AvatarMessageRow` からブランドアイコンを撤去し、本文を左端へ詰める。**
  **チームビュー（`TeamTimelineView`）とアゴラの発言者行のアイコンは残す**。あちらは複数エージェントの
  発言が混ざるタイムラインで、アイコンが話者の識別に必要。チャットは 1 対 1 なので識別価値が無い。

## 結果

- transcript から回転アニメーションが消えた（実行中インジケータは Thinking の orb だけになる）。
- `AgentMessageCell` / `ThinkingIndicatorCell` / `CompactingIndicatorCell` の `descriptor` は
  未使用の格納プロパティとして残っている。`DashboardFeatureTests/ChatMessageCellsRenderTests.swift` が
  これらのイニシャライザを呼んでおり、消すとスコープ外のテストが壊れるため。
- 回帰保護: `DesignSystemTests/ChatToolCallTokenTests`（トークンの値契約をライト／ダークで検証）と
  `SessionFeatureTests/AcceptanceQuietChatChromeTests`（アイコン引数の不在・パレット 4 分岐・
  `ChatMessageCellsCommon.swift` に `AgentBrandIcon`/`AgentAvatar` が再登場しないこと）。
