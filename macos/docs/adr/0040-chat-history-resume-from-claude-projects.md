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

## 2026-10-23 の変更方針

開いている会話を二重に再開しないよう、Claude Code と Codex の履歴取得時に、全プロジェクトの現行セッションが使用している会話を除外する。照合にはハーネスと native 会話 ID の組を使う。読み込み後と再開直前にも現在のセッションと照合する。

削除時の表示名は、現行セッションの復元登録とは寿命が異なるため、Phlox の保存領域の独立した JSON に記録する。既存の `JSONFileStore` による原子的保存と権限処理を使い、Claude と Codex の会話ファイルは変更しない。名前の保存に失敗した場合は削除を失敗として扱い、セッション登録を残してエラーを表示する。

履歴データには任意の保存名を持たせる。保存名があれば表示名として優先し、ない場合は既存の会話本文による名前生成を使う。新規チャットのポップオーバーと既存の履歴開始画面は同じ取得規則を使い、常駐プロセスの投影にもその結果を渡す。保存前に削除済みの名前は復元できない。

`sessions.json` に履歴名を追加する案は採らない。通常保存と破損データの退避・再保存に、新しい保持規則を持ち込まずに済むためである。

実Codexでの再開検証では、本文の受信後も実行中の表示が残り、以前のターンの使用量通知の後に新しいターンの正規化済み開始・完了通知が欠ける状態を観測した。使用量通知と再開応答の順序を変えた回帰テストで、仮のターンIDが新しい開始を拒否する条件を再現した。使用量で仮に捕捉したターンと、開始通知で確定したターンを既存の状態で区別し、置き換えた過去のIDも終了済みとして扱う。再開後の本文だけでなく、完了通知と待機状態への復帰も検証する。
