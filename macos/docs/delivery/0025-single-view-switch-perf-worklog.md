---
status: completed
last-verified: 2026-07-29
---

# 0025: シングル表示のセッション切替が遅い問題の調査と修正

関連: [ADR 0139](../adr/0139-transcript-text-selection-and-render-budget.md) /
[ADR 0030](../adr/0030-transcript-eager-layout-and-one-way-composer-metrics.md)（非遅延レイアウトの規定）

## 何をしたか

「シングルビューでセッションの切り替えがもっさりする」という報告を、計測 → 真因特定 → 修正 → 再計測の
順で処理した。結果、切替 1 回あたり **2447ms → 177ms（13.8 分の 1）**、ハング **11 件 → 0 件**。

## 計測基盤（再現手順は `macos/scripts/measure-single-switch-procedure.md`）

- 稼働中のリリース版を落とさずに済ませるため、別インスタンスとして計測用ビルドを併存させた。
  `PHLOX_DATA_DIR` で実データのコピーを、`PHLOX_DEFAULTS_SUITE` で UserDefaults を隔離する。
- ad-hoc 署名（`CODE_SIGN_IDENTITY="-"`）は同梱 Sparkle.framework とチーム ID が不一致になり
  起動直後に dyld がロードを拒否する。Developer ID Application 署名 + `CODE_SIGN_STYLE=Manual` が要る。
- 操作は**サイドバーのセッション行を CGEvent でクリック**する（実際のユーザー操作経路）。
  同名プロセスが複数走るため、frontmost の pid を毎回検証してからクリックを送る。
- 指標はメインスレッドのサンプル数（Time Profiler 1ms 間隔 ≒ ms）。
  Instruments のハング検出は閾値未満を 0 件にするため、閾値より下も比較できるようにした。

## 判ったこと（詳細は ADR 0139）

真因は `.textSelection(.enabled)`。SwiftUI のこの modifier は環境値の伝播先の `Text` 1 個ごとに
選択可能な表現を構築し、1 個あたり約 1.8ms かかる。`FileChangeCell` が diff 1 行ごとに `Text` を
作ってこれを当てていたため、コストが行数に対して上限なく積み上がっていた。切替 1 回 2447ms のうち
1894ms（77%）がこれだった。

否定した仮説: CoreText（0.7%）・markdown パース（0.1%）・ファイル I/O（0%）・
`.fixedSize` の理想サイズ計測（外しても改善せず）・`.textSelection` の適用箇所（親へ寄せても同値）。

## 変更したもの

| ファイル | 内容 |
|---|---|
| `ChatTextSelectionPolicy.swift`（新規） | 選択可否の一元管理。prose は有効、diffLines は無効 |
| `TranscriptRenderBudget.swift`（新規） | 描画コスト予算で表示ブロック数を決める純関数 |
| `ChatMessageCells+Structured.swift` | diff 行の選択を外し、file section ごとのコピーボタンを追加 |
| `ChatTranscriptView.swift` | 予算による窓のクランプ、reveal の優先 |
| `ChatTranscriptGrouping.swift` | ブロック化の二重実行を避ける overload を追加 |
| `ChatCodeBlock.swift` / `ChatMessageCells+Basic.swift` / `ChatSessionAccessories.swift` / `RichMarkdownView.swift` | `.textSelection(.enabled)` → `.chatTextSelection()` |

## 進め方で効いたこと / 詰まったこと

- **プロファイルのシンボルだけでは真因に届かなかった**。Release ビルドではアプリ側のシンボルが
  ほぼ解決できず（`<deduplicated_symbol>` 48.9%）、種別への帰属ができない。
  環境変数で**セルを 1 種別ずつプレースホルダへ差し替えて計測する**アブレーションで初めて特定できた。
  差し替えは「生成しない」ことが要る（`.hidden()` で隠すだけではレイアウトコストが消えない）。
- **静的な内容統計から回帰でコストを説明しようとして失敗した**。diff 行数・markdown 要素数を
  説明変数にした最小二乗フィットは負の係数を出し、誤差も大きかった。素直に計測を分割すべきだった。
- **計測が無言で無効になった事故が 1 回**。SIGTERM 終了後の再起動ではサイドバーのプロジェクト行が
  折りたたまれたまま始まり、クリックがセッション行ではなく開閉ボタンを押していた。
  「現行設定でもハングが 0 件」というベースラインと矛盾する結果が出たことで気づいた。
  以後、計測開始直前の画面をスクリーンショットで残して毎回目視確認する手順にした。
- **座標のずれ**。ウィンドウの Y 原点を 25 と仮定していたが実際は 33 で、小さなボタンのクリックが
  外れていた。`kCGWindowBounds` を読んで確かめること。
- **独立レビューが 2 ラウンドとも実在の欠陥を出した**。1 回目は「長文テキストのセッションで
  『以前のメッセージを表示』を押しても増えない」、2 回目は 1 回目の修正が反例を残していたこと
  （下限の錨を定数に置いたため、既定で下限より多く表示できているセッションで効かない）。
  いずれも実機・回帰テストで再現を確認してから直した。
  2 回目は「decision-log を訂正済み」という PM の報告が実態と違う点も指摘された（原文が未修正だった）。

## 残っていること

- 決定 1 適用後も、fileChange 245ms・agentMessage 187ms・骨格 107ms が残る（N=50 時）。
  これらは「小さなビューが多い」ことに由来し、AppKit のテキスト描画へ作り替えない限り
  下がらないと見ているが、**この見立ては未検証**。
- 長文テキストのみのセッションは、下限の 6 ブロック表示でも約 250ms かかり目標に届かない。
  計測した 4 セッションでは発生していないが、下限件数そのものが高コストな内容では予算で守れない。
- 重み定数は較正値であり、コストの内訳が変われば再較正が要る（ADR 0139 決定 4）。

### 調査中に見つけた、今回は触っていないもの

- **`ChatTranscriptView` の `onChange(of: viewModel.id)`（`window.reset()` / `autoFollow.sessionDidChange()` /
  `scheduleScrollToBottom`）はアプリ全体で一度も走っていない。** 呼び出し元は
  `ChatSessionView.swift` と `GridChatColumn.swift` の 2 箇所だけで、どちらも `.id(session.id)` の下に
  あるため viewModel が入れ替わるとビュー自体が作り直され、`onChange` は発火しない。
  `.id()` を外す将来の変更では、この経路が初めて生きることになる。今回は触っていない。
- **切替のたびにトランスクリプト全体を 2 回走査していた。** ブロック化（`makeBlocks`）が
  表示件数の決定と `visibleSlice` で二重に走っていたのは今回直した（`visibleSlice(fromBlocks:)`）。
  一方 `InputHistoryPolicy.entries(from: items)` による全件走査＋Set 構築は残っている。
  実測では支配的でなかったため触っていない。
