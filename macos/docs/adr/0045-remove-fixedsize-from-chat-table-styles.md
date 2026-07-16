---
status: active
last-verified: 2026-07-07
---

# ADR 0045: チャット Markdown 表スタイルから .fixedSize を外し、リサイズ時のレイアウト非収束ループを解消する

> **このファイルの役割**: 2026-07-07 の「チームビュー CPU 暴走」（実体は表レイアウトの非収束）に対する修正の決定・文脈・結果。
> **書かないもの**: 現行のテーマ構造（→ コード `RichMarkdownView.swift`）、run の作業経緯（→ `delivery/0024-teamview-cpu-fix-worklog.md`）。

## 文脈

ADR 0043 のチームビュー実機検証中に、ユーザーがウィンドウを手動リサイズした際 CPU が 100% に固着しアプリ全体がフリーズする暴走が発生した。実機診断（sample 2本）の結果:

- main thread の 99% 超が `GraphHost.flushTransactions` 配下で、支配的フレームは **MarkdownUI の表デコレーション**（`TableBounds.init` / `TableBorderView.body` / `TableBackgroundView.body` / `tableDecoration` の GeometryReader）だった。
- リサイズ終了後も回復せず（5分以上・`_resizeWithEvent:` の追跡ループ内で固着）、ControlServer も main actor 飢餓でタイムアウト＝アプリ完全フリーズ。
- 静的表示では 0%。トリガーは「表を含むコンテンツ可視＋リサイズ／再前面化」。
- 表リッチ化（ADR 0044 と同 run の task-4・`ab51e71`）が `.table`/`.tableCell` スタイルに付けた **`.fixedSize(horizontal: false, vertical: true)`（表本体・セル両方）** が、MarkdownUI のアンカーベース表測定（`TableBounds`）と Phlox のチャット文脈（`ScrollView`＋`LazyVStack`＋可変幅）の組み合わせで幅⇄高さの帰還ループを形成していた。

## 決定

1. `chatMarkdownTheme` の `.table`／`.tableCell` スタイルから **`.fixedSize(horizontal: false, vertical: true)` を除去する**（`2824283`）。ゼブラ・ヘッダ強調・罫線・スケール追随余白の視覚仕様は維持する。
2. この2箇所に fixedSize を**再導入しない**（コード内 NOTE で明示）。MarkdownUI 純正テーマ（GitHub 等）が同じイディオムを使っていても、Phlox のチャット文脈では非収束を引き起こす。
3. **自動回帰テストは置かない**。headless（NSWindow＋NSHostingView＋実物 ChatItemView＋実物大コンテンツ＋連続リサイズ）を2段階の忠実度で試みたが未修正コードでも再現せず（WindowServer 実表示の update cycle に依存）、検出力のないテストは誤った安心感になるため。回帰確認は実 Debug 起動の runtime 手順（worklog 0024 記載）で行う。

## 棄却案

- **MarkdownUI の fork／パッチ**: コスト大。Phlox 側のスタイル指定除去で収束が実証されたため不要。
- **巨大表の描画打ち切り（行数上限）**: ループは表の大きさでなく収束性の問題であり、対症療法になるため棄却。
- **検出力のない headless 回帰テストの配置**: 未修正コードで pass してしまうテストは品質シグナルを汚すため棄却（テスト規律）。

## 結果

- 同一の再現レシピ（表可視のチームビュー＋AX 段階リサイズ＋実マウスドラッグ＋再前面化）で、未修正 99–100% 固着 → 修正後 0〜2.7% 収束を実測（A/B）。
- DashboardFeature 全 816 テスト green・既存表スモーク 4 テスト無改変で green。視覚パリティは ImageRenderer で確認。
- 残る検証: 実機のライト/ダーク・幅違いでの見た目一瞥と、ユーザー操作による最終リサイズ確認（run の task-3）。
