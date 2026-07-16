---
status: active
last-verified: 2026-07-16
---

# ADR 0020: 送信済みメッセージの画像添付バッジをクライアント側 side-map で表示する（サーバ非依存）

> **このファイルの役割**: wave-8 で、画像を添付して送信したユーザーメッセージに「添付があったこと」をチャット上で示すバッジを、サーバ/ワイヤを変えずクライアント側だけで実現した決定を記録する（macOS デスクトップ版と同じ方針）。
> **書かないもの**: 添付の送信・検証（`addAttachments`/`normalizeAttachment` の現行仕様 → [architecture/overview.md](../architecture/overview.md)）。

## 文脈

iOS の入力欄は画像添付（`SendAttachment`・最大4枚）を送信できるが、送信後のチャット吹き出しに添付があったことが表示されず、デスクトップ（macOS）と体験が揃っていなかった。

調査の結果: ドメイン型 `ChatMessage` にもサーバワイヤ `ChatMessageDTO`（`GET /messages`）にも添付メタは無く、`api.send` の戻り `SendResult(accepted:message:)` は**メッセージ ID を返さない**。凍結 API 契約 `mobile-api-extensions-contract.md §5` も `POST /send` の `images` だけを定義し、応答側に添付は無い。さらに `SessionDetailViewModel.sendMessage` は送信後 `refresh()` でサーバ由来 `chatMessages` を**全置換**する。macOS 側は既にサーバ非依存で「送信時にクライアントで添付メタ（filename/mediaType）だけ保持し、ユーザーバブル下にバッジ表示」する方式（`ChatUserAttachment` / `ChatAttachmentBadge`）を採っていた。

## 決定

サーバ・ワイヤ・凍結 API 契約・`ChatMessage` を**一切変更せず**、クライアント側だけで表示する（macOS 準拠）。

- **突き合わせ純関数** `SessionAttachmentReconciler.reconcile(messages:pending:assigned:)`: 送信時に積んだ `Pending(text, count)` を、`messages` を末尾から走査して「送信テキストに一致する最新の**未割当**ユーザーメッセージ」へ割り当てる。一致が無ければ pending を残し、割当済み id は再割当しない（二重割当もしない）。戻りは全体マップと残 pending。
- **ViewModel の side-map**: `SessionDetailViewModel` が送信成功後（添付ありのみ）に `pendingAttachmentSends` へ積み、`chatMessages` を更新する全経路（`didSet`）で reconcile して `attachmentCountsByMessageID`（message.id 起点）へ反映する。message.id で保持するため、`refresh()` によるサーバ snapshot 全置換に**耐える**（毎回 reconcile で再割当）。
- **表示**: `DSChatBubble` に `attachmentImageCount: Int?`（既定 nil）を追加し、user バブルのテキスト下に控えめなバッジ（`Image(systemName: "photo")` ＋ `attachmentBadgeText(count:)`＝1枚「画像」/複数「画像 ×N」）を出す。`SessionDetailView` の `.user` 行で `viewModel.attachmentImageCount(forMessageID:)` を配線。iOS の `SendAttachment` はファイル名を持たないため枚数表示（macOS はファイル名表示）。

## 結果

- 画像を添付して送信すると、そのユーザーメッセージに「画像 / 画像 ×N」バッジが出て、添付があったことが分かる。サーバ往復・ワイヤ・凍結契約は不変（クライアント完結）。
- 凍結受け入れ `SessionAttachmentReconcilerAcceptanceTests` が「最新の未割当へ割当・一致なしは pending 保持・再割当しない」を固定。
- **前提/劣化**: 突き合わせは送信テキスト一致。同一テキストの連投は末尾優先の順序で解決。サーバがテキストを変換する等で一致が取れなければバッジ非表示に穏当に劣化（誤バッジは出さない）。画像本体（サムネイル）は表示せずバッジのみ（macOS 準拠・ストレージ肥大回避）。

## 却下した代替案

- **サーバ API を拡張し応答メッセージに添付を載せる**: 現行の凍結契約外でサーバ変更を伴う。クライアント完結で足りる。
- **`send` の応答 ID で突き合わせる**: `SendResult` は ID を返さないため不可能。
- **サムネイル画像本体を表示する**: iOS には送信時の `previewData` があり実現可能だが、ストレージ肥大と、macOS が採るバッジ方式（「デスクトップ同様」）との一致を優先し、バッジ（枚数）に留めた。
