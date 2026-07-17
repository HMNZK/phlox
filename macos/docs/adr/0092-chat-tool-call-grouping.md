---
status: active
last-verified: 2026-07-17
---

# 0092: チャットのツールコール連続表示のグループ集約と identity 設計

## 文脈

トランスクリプトでコマンド実行（ツールコール）が1件ずつセルとして縦に並び、連続実行時にチャットが読みにくかった。集約表示を入れるにあたり、ADR 0030 の描画方式（非 Lazy VStack＋末尾ウィンドウ描画）と衝突しない **ForEach identity の安定性**が核心的困難だった: グループの id が後続 item の追加で変わると、SwiftUI がセルを破棄・再生成してスクロール位置とアニメーションが壊れる。

## 決定

1. **純関数 `ChatTranscriptGrouping.blocks(from:)`** が item 列を `ChatTranscriptBlock`（`.single` / `.commandGroup(id:items:)`）へ畳む。連続する commandExecution 系 item を1グループに集約する。
2. **グループ id は先頭 item の id**（`head item.id`）。グループ末尾への item 追加で id が変わらず、ForEach identity が安定する（append しても既存セルは再利用）。凍結 `AcceptanceToolCallGroupingTests` が「flatten 等価」（blocks を展開すると元の item 列に一致＝欠落なし）と「append で既存 block id 不変」を固定する。
3. **末尾ウィンドウとの整合**: `visibleSlice` はウィンドウ境界でグループを分割してよい（部分ブロック）が、**外側 id は先頭 item の id のまま**保つ。ウィンドウ拡張は単調（境界移動で id が付け替わらない）。ジャンプは `scrollTargetID(containing:in:)` が「その item を含むブロックの id」を両経路（通常スクロール・検索ジャンプ）で解決する。
4. 表示は `CommandGroupCell`（`ChatMessageCells+CommandGroup.swift`）。`CommandGroupPresentation.shouldRender = isRunning || !rows.isEmpty` で空グループを描画しない。

## 棄却した代替案

- **グループ id を内容ハッシュや (先頭,末尾) ペアで導出** — item 追加のたび id が変わり identity が壊れる。
- **VM 側で集約済みモデルを保持** — 描画都合の集約を状態化するとイベント追記との整合維持が複雑化する。描画直前の純関数変換なら入力（item 列）が常に正。
- **DisclosureGroup 等での遅延展開** — ADR 0030 の非 Lazy 前提（全高さ確定）を崩すため不採用。

## 結果

集約後もトランスクリプトの item 全件がブロック経由で到達可能（flatten 等価）で、append 時のセル再生成なし。凍結 `AcceptanceToolCallGroupingTests`＋白箱 `ChatTranscriptGroupingWhiteboxTests` で固定。
