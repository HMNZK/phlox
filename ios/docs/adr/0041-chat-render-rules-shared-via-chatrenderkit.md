---
status: accepted
last-verified: 2026-07-31
---

# ADR 0041: チャット表示の純関数を `ChatRenderKit` へ 1 本化し、モバイルにも同じ表示規則を適用する

> **このファイルの役割**: デスクトップ（macOS）で先に入ったチャット表示の刷新（ADR 0142〜0147）を
> モバイルへ持ち込むにあたり、**規則の置き場所**と**どこまで見た目を揃えるか**を決めた理由。
> **書かないもの**: 各表示規則そのものの根拠（→ macOS の
> [ADR 0144](../../../macos/docs/adr/0144-quiet-chat-chrome.md) /
> [0145](../../../macos/docs/adr/0145-tool-group-recap-header.md) /
> [0146](../../../macos/docs/adr/0146-diff-code-view.md) /
> [0147](../../../macos/docs/adr/0147-chat-code-card-and-header-dedup.md)）、
> ツールコール集約の畳み方（→ [ADR 0026](0026-ios-single-toolcall-grouped-row.md) / [0038](0038-command-group-cost-bounding.md)）。

## 文脈

macOS 1.4.0 で、transcript の表示を作り直した: 装飾の撤去、ツール実行グループの見出しをコマンド原文にする、
diff を行番号付きのコードビューにする、diff とコマンド実行を同じ枠線付きカードへ収める。

モバイルはこの刷新を受けておらず、同じ transcript を見ているのに、mac では「何をしているか」が読める画面、
iOS ではアイコンと固定文字列 `ツール実行 ×N` が並び diff は生テキスト、という体験差ができていた。

問題は移植方法だった。macOS の実装は**表示の純粋計算**（diff の行分類・行番号採番、Swift／シェルのトークナイザ、
見出し・動詞・ツール名の導出）を macOS 専用パッケージ `SessionFeature` の中に持っており、iOS からは import できない。
そのまま書き写すと、同じ規則が macOS と iOS の 2 箇所に生まれる（`ChatRecapIOS` で既に一度起きている）。

## 決定

**純粋計算は共有ターゲット `ChatRenderKit` へ引き上げて 1 本化し、見た目は「情報の出し方」だけ揃える。**

- **`ChatRenderKit` を `macos/Packages/AgentDomain` パッケージ内の新ターゲットとして作る。** Foundation のみに依存し、
  `platforms: [.macOS(.v14), .iOS(.v17)]`。新しいパッケージは作らない——iOS は既にこのパッケージを path 依存で
  参照しているので、配線が product 追加だけで済む（ADR 0001 の共有方針の延長）。
  移したのは `ChatDiffClassifier`（行分類・採番）/ `ChatCodeTokenizer`（Swift・シェル）/ `ChatCommandToolLabel` /
  `ChatFileChangePresentation`（動詞・増減行数・見出し）/ `ChatReasoningPresentation` / `ChatCommandGroupTitle`。
  **macOS 側は再実装を残さず、共有実装を呼ぶだけにした**（残ってよいのは型変換・トークン→色の対応付け・メモ化）。
- **移設は振る舞いを変えない。** macOS 側の凍結受け入れテストを **1 行も変えずに** pass させることを条件にした
  （`git diff --exit-code` で機械判定）。ついでの改善・命名変更はしない。
- **見た目は「情報の出し方」だけ揃える（ユーザー決定）。** 枠線付きコードカード・コマンド原文の見出し・
  diff コードビュー・装飾撤去は揃える。**余白・文字サイズ・タップ領域（`DSTouch.minSize`）・既存の行ウィンドウ
  （50 件ずつ表示）はモバイル向けのまま残す**。レイアウト値の完全一致は求めない。
- **器の分担**: `DSChatCodeCard`（枠線・角丸・背景・クリップのみ）が器を持ち、
  **ツール実行グループ自体は器を持たない**（見出しと展開状態だけ）。外側にも背景を敷くと、ファイル変更カードと
  見た目が割れ、カードの入れ子で枠が二重になる。
- **diff の行は横スクロールで到達可能にする。** iPhone の幅ではコード行が必ず溢れる。折り返さず横スクロールにし、
  **パス見出しは横スクロールの外**へ置く（内側だと幅の提案が nil になり中略が効かず、スクロール範囲がパス長で決まる）。
- **markdown 用の既存ハイライタ（`DesignSystemIOS.CodeHighlighter.tokens(for:language:)`）は据え置く。**
  `ChatRenderKit` の Swift トークナイザとは出力が異なるため、1 本化すると markdown コードブロックの見た目が変わる。
  本 run のスコープ外なので、**Swift トークナイザが 2 実装ある状態を意図的に受け入れた**（diff・コマンドは
  共有側、markdown は既存側）。
- **行の種類は `ChatRowKind.forMessage(_:)` に 1 本化**し、セッション詳細とサブエージェント詳細の両方がこれで分岐する。
  `default:` を置かず、メッセージ種別が増えたらコンパイルエラーになる形にする。

## 結果

- モバイルでも、ツール実行の見出しが「最後に実行したコマンドの原文」になり、diff が行番号・構文ハイライト付きの
  コードビューになった。ファイル変更は既定で折りたたみ、見出しに `編集済み <ファイル名> +A -1` を出す。
- サブエージェント詳細も同じ器になった。巨大本文の省略（`renderedBody`）は**コマンド出力にのみ**適用し、
  **diff には適用しない**（途中で切ると採番・分類が壊れるため。既定折りたたみで描画量を抑える）。
- 既存テストのうち `"ツール実行 ×N"` を期待していた 3 ファイルは、**フォールバック規則**（コマンドが 1 件も無い
  グループ）の検証へ書き換えた。件数の保証は捨てていない。
- 既知の積み残し: サブエージェント詳細の diff に描画行数の上限が無い（既定折りたたみが実質の歯止め）。
  ツール実行グループのヘッダ構築が毎描画 O(N)。いずれも実測していないため、必要になってから対処する。
- 回帰保護: `AgentDomainTests/ChatRenderKitTests`（採番の境界・壊れたヘッダ・オーバーフロー・トークナイズ・
  ツール名・動詞・見出しクランプ）、`FeaturesTests/AcceptanceIOSToolCallCardTests`・
  `AcceptanceIOSFileChangeCodeViewTests`・`AcceptanceIOSReasoningAndSubAgentTests`、
  `DesignSystemIOSTests/AcceptanceDSChatCodeCardTests`。
