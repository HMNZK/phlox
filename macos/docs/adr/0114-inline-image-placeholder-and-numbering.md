---
status: accepted
last-verified: 2026-07-22
---

# ADR 0114: 添付画像に番号を振り、本文へ `[Image #N]` をカーソル位置で埋め込む（表記は AgentDomain に単一化）

## 文脈

composer の画像添付は、本文テキストとは完全に独立したリスト（macOS は `ComposerAttachmentStore`、iOS は
`SessionDetailViewModel.attachmentItems`）として保持されていた。そのため:

- 本文のどこに画像を差したいのかをユーザーが表現できない。エージェントにも位置が伝わらない。
- 複数枚添付したとき、チップ／サムネイルのどれが何枚目なのかを指し示す語彙が無い（表示はファイル名か mediaType のみ）。

Claude Code CLI は画像をペーストするとカーソル位置に `[Image #1]` というテキストを挿入し、同じ番号で添付を示す。
この挙動を Phlox の macOS / iOS 双方に入れることにした。

## 決定

1. **埋め込みはテキストのプレースホルダ `[Image #N]`**。入力欄に画像そのものをインライン描画（`NSTextAttachment` 等）はしない。
   本文が素の `String` のままなので、送信・下書き保存・IME・サジェスト等の既存経路を作り替えずに済む。
2. **採番は 1 始まりで、欠番を詰めない**。`nextNumber(after:)` は既存番号の最大値 + 1。添付を削除しても残りの番号は
   振り直さず、本文中のプレースホルダも書き換えない（書きかけの本文を勝手に編集しないため）。削除した添付の
   プレースホルダだけを本文から取り除く。
3. **表記・挿入・削除の規則は共有パッケージ `AgentDomain` の `ComposerImagePlaceholder` に1箇所だけ置く**。
   macOS（`SessionFeature`）と iOS（`PhloxKit`）は path 依存でこれを共有し、二重定義を作らない。
   - `text(for:)` / `nextNumber(after:)` / `inserting(number:into:cursorUTF16:)` / `removing(number:from:)` の4純関数。
   - オフセットは **UTF-16** で扱い、書記素クラスタ境界へ丸める（絵文字・結合文字を割らない）。
   - 挿入時は前後が空白・改行でなければ半角スペースを補い、削除時は削除位置に隣接する半角スペースを1つだけ畳む。
     テキスト全体の正規化・trim はしない。
4. **CLI へ送るペイロードの並びは変えない**（本文 → 画像ブロックの順）。本文中の `[Image #N]` の位置に画像ブロックを
   差し込む「本当の意味での interleave」はしない。Claude Code もそうしておらず、既存の送信契約
   （`ComposerAttachmentWhiteboxTests` が凍結）を壊さないため。
5. **添付の入口ごとの挿入位置**:
   - ペースト（macOS）・PhotosPicker（iOS）: **カーソル位置**
   - 「+」ボタン（macOS）: **本文末尾**。この経路は入力欄のカーソルを取得できないため。既存の `@path` 挿入と同じ流儀。
6. **本文とプレースホルダの対応は双方向**。チップの × で添付を消せば本文の `[Image #N]` も消え、本文から
   `[Image #N]` を消せば対応する添付も外れる。当初は「添付 → 本文」の片方向だけを実装したが、実機確認で
   「本文からプレースホルダを消しても画像が残るのは直感に反する」と判断し双方向へ変更した。
   - 判定は `numbersRemoved(from:to:among:)`。**oldText に無かった番号は決して返さない**。これが安全弁で、
     本文に紐づかない添付（Control API 経由で積まれた画像など）や、挿入した直後の添付を誤って外さない。
   - トークンは全体一致で判定する（`[Image #1]` が `[Image #12]` の一部として誤マッチしない）。
   - **送信による本文クリアは添付を外さない**。macOS は送信ペイロード（`buildChatInputs`）がライブの
     `attachmentStore` を読むため、ここで外すと画像が送られない／`turnStart` 失敗時に添付が残らない。
     `ChatSessionViewModel.syncAttachmentsWithDraftEdit` がクリア直前の本文を覚えて読み飛ばす。
     iOS は送信前に `backupItems` を控える設計なのでこの防護は不要。

## 結果

- ユーザーは「この画像を見て」「1枚目はこれ、2枚目は…」を本文で表現できるようになった。
- 添付チップ／サムネイルに `#N` バッジが出て、本文のプレースホルダと1対1で対応する。本文からプレースホルダを
  消せば添付も外れる（逆も同じ）ので、対応が画面上で崩れない。
- 画像添付は引き続き Claude のみ対応（`ComposerAttachmentCapability`）。他エージェントでは従来どおりテキストペーストへフォールバックする。
- 既存のペースト経路 `SubmitAwareTextView.onPasteImage`（`ChatFixTask4PasteAcceptanceTests` が凍結）は残し、
  番号を返す `onPasteImageOutcome` を**追加**して後方互換を保った。`onPasteImageOutcome` が設定されていればそちらが優先される。

## 関連

- 実装: `macos/Packages/AgentDomain/Sources/AgentDomain/ComposerImagePlaceholder.swift`、
  `macos/Packages/SessionFeature/Sources/SessionFeature/ComposerAttachments.swift` / `ChatComposer.swift` / `GridChatColumn.swift`
- iOS 側の決定は `ios/docs/adr/0025-ios18-textselection-for-cursor-aware-input.md`
- 作業ログ: `macos/docs/delivery/0014-inline-image-attachments-worklog.md`
