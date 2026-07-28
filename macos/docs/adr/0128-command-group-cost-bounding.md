---
status: active
last-verified: 2026-07-27
---

# 0128: ツール実行カードは閉状態で行データを作らず、展開時も行数を有界化する

## ステータス

採択・実装済み（2026-07-27, `feature/tool-call-collapse-threshold`）。[ADR 0127](0127-transcript-window-counts-blocks.md) と対で読む。

## コンテキスト

ADR 0127 で表示窓がブロック単位になった結果、**1つの `commandGroup` が数百〜数千件のツール実行を抱えうる**ようになった（従来は窓が item 数を 50 に絞っていたため、可視グループの中身も高々 50 件だった）。この前提変化で、既存の `CommandGroupCell` に2つの問題が露出した。

1. **閉じていても全件を走査していた。** `CommandGroupPresentation.init` は折りたたみ状態でも group 内の全 item を `compactMap` + `filter` して `rows` を作っていた。transcript は非 Lazy VStack（ADR 0030）でストリーミングのたびに body が再評価されるため、件数に比例した構造体生成が毎 tick 走る。
2. **展開すると全件を一度に描画していた。** 数千行を非 Lazy VStack へ流すと、ADR 0030 が対処した CPU 暴走・ハングの再発経路になる。

加えて ADR 0127 の副作用として、1件のツール実行が `commandGroup` になったことで、**出力が空・非実行中の単独コマンドが `shouldRender == false` でカードごと消える**回帰が入っていた（変更前は `.single` として常に見えていた）。

## 決定

1. **ヘッダと行データを型で分ける。**
   - `CommandGroupHeader`（`title` / `timestamp` / `isRunning` / `shouldRender`）— **行データを保持しない**。閉状態の描画はこれだけを使う。
   - `CommandGroupRowWindow.slice(items:lastTranscriptID:isTurnRunning:limit:) -> CommandGroupRowsSlice` — 展開時にだけ呼ぶ純関数。
   - 行構築の呼び出しは `if isExpanded { ... }` の内側に置く。
2. **展開時にも行数の窓を置く。** `CommandGroupRowWindow.defaultLimit = 50` / `expandStep = 50`。表示対象行の末尾 50 件を出し、残りは `hiddenRowCount` として「残り N 件を表示」ボタンで段階展開する（transcript 本体の「以前のメッセージを表示」と同じ操作モデル）。
3. **空出力フィルタは唯一の行には適用しない。** iOS の既存規則（[iOS ADR 0026](../../../ios/docs/adr/0026-ios-single-toolcall-grouped-row.md)）を macOS へ移植する。`shouldRender = isRunning || items.count == 1 || 出力が空でない item が1件以上ある`。

## 結果

- 閉じたカードの body 評価コストがグループ件数に依存しなくなる（`shouldRender` の短絡走査だけが残る。文字列・構造体の生成はしない）。
- 展開しても一度にレイアウトされる行は 50 行までに有界化される。ADR 0030 の再入禁止（レイアウトコストの無制限化）を守る。
- 出力が空のツール実行が1件だけのとき、カードは従来どおり表示され、展開すれば `$ <コマンド>` が読める。
- 旧 `CommandGroupPresentation` は削除した。

## 既知の限界（意図的に受け入れたもの）

- `shouldRender` は「出力が空でない item が1件でもあるか」を配列から判定するため、**全件が空出力という最悪ケースでは N 件を走査する**。前計算なしに O(1) にはできない。生成コストは伴わない（`contains(where:)` の短絡評価のみ）ため受け入れた。
- 実行中のグループでは、新着 item が末尾へ積まれるぶん「残り N 件を表示」で開いた古い行が再び窓の外へ押し出される。transcript 本体の窓と同じ性質であり、`rowLimit` は縮まないので操作が巻き戻ることはない。
- **「閉状態で行データを作らない」は SwiftUI の body 評価を単体テストから観測できないため、ソース検査の白箱テストで固定した**（`slice` の呼び出しが `if isExpanded` ブロック内に現れることを実ソースから検証する）。整形の変更で偽陽性になりうる脆さがあるが、eager に書き戻すと落ちることは変異試験で確認済み。

## 凍結テスト

- `macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceCommandGroupRowWindowTests.swift` — 5000件でもヘッダが正しい・展開直後の行数 ≤ 50・`hiddenRowCount`・単独空出力の描画・複数件全空出力の非描画
