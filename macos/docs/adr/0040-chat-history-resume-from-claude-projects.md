---
status: active
last-verified: 2026-07-06
---

# ADR 0040: チャットの履歴再開は ~/.claude/projects の JSONL 直読み＋off-main リアクティブロードで実現する

> **このファイルの役割**: 履歴一覧のデータ源・読み取り方式・ロード方式の決定理由。
> **書かないもの**: 現行のコンポーネント構成（→ architecture/chat-mode-ux-components.md）。

## 文脈

新規 Claude チャットの中央に過去セッション履歴を表示し、選択で `--resume <session-id>` 再開したい（chat-ux-batch 項目C/D）。Claude Code は `~/.claude/projects/<cwd をサニタイズした名前>/<session-uuid>.jsonl` に1セッション1ファイルで履歴を持ち、ファイル名がそのまま resume 用 ID になる。

## 決定

1. **データ源は JSONL の直読み**（`ClaudeSessionHistoryDiscovery`）。cwd サニタイズは「英数字以外→`-`」。最初の `"type":"user"` 行からプレビュー・時刻・gitBranch を抽出し、sidechain（サブエージェント転写）・コマンドメタ（`<` 始まり）を除外。mtime 降順・20件。読み取りは有界（先頭200行/256KiB）。
2. **行の読み取りはバイトレベルで `0x0A` 分割してから UTF-8 decode**（`JSONLByteLineReader`）。チャンク境界＝文字境界という前提は日本語データで 63% の silent 喪失を起こす（fix round で実測 2000→747 行を根治）。
3. **履歴ロードは off-main（Task.detached）＋リアクティブ表示**。同期ウォームは実測で MainActor を約1秒ブロックするため禁止。ロード完了で observable キャッシュが更新され SwiftUI が一覧を表示する。provider 呼び出しは VM 生成につき高々1回。
4. 転写は `ClaudeSessionTranscriptLoader` が user/assistant テキストのみ ChatItem 化（末尾500件）。resume 失敗時は transcript を空へ戻し履歴一覧へ復帰（再試行可能）。

## 棄却案

- Phlox 自身の transcripts/ キャッシュを履歴源にする: Phlox 経由セッションしか含まれず、CLI 直用の履歴が拾えない。
- 同期ロード（init ウォーム）: 実測 約1秒の MainActor ブロックで棄却。
- `claude --resume` の対話 UI 呼び出し: チャットモード（headless）と両立しない。

## 結果

- 一覧は現在の cwd に紐づくもののみ（別プロジェクト履歴はスコープ外）。
- resume の実行系は既存 `ClaudeChatClient.resume(sessionRef:)`（`--resume` respawn）をそのまま使用。
- 契約テスト: `ClaudeSessionHistoryAcceptanceTests`（UTF-8 境界再現含む）/ `ChatHistoryStartAcceptanceTests`（await 形）。
