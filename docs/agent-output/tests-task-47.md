---
task: task-47
status: completed
---

task-47（UX-05b）の受け入れ検査を新規作成した。製品コード・契約・台帳は未変更。コミットしていない。他担当の未コミットファイルと `/tmp/ui-ux-wt-*` には触っていない。

## 作成物

- `tasks/frozen/staged/AcceptanceTranscriptMarkdownPresentationTests.swift`（実パス `macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptMarkdownPresentationTests.swift`。先頭コメントに実パス。Swift Testing。`TranscriptMarkdownPresentation` / `bodyColor` 付き入口未実装のコンパイル RED が正常）
- `tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift`（実パス `macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask47Tests.swift`。契約の PM 目視ハーネス。固定シナリオは常時実行、ウィンドウ保持だけ `PHLOX_PM_VISUAL_TASK=47`）
- `.claude/scripts/task47-wiring.rb`（`TASK47_BASELINE` 必須、契約 `baseline_commit` 一致、HEAD/ブランチ名拒否、祖先確認、基準に `TranscriptMarkdownPresentation.swift` 不在かつ task-46/task-40 完了、凍結テストと rb の blob 同一性、製品配線検査、`--selftest`）
- `docs/agent-output/tests-task-47.md`

## 期待値の出所

正本は `tasks/task-47.md`。task-46 の `TranscriptItemPresentation` 契約と task-40 の `TranscriptTypography` 実コード、ADR 0147 を task-46 が置き換えた決定（見出しは「処理の詳細（N件）」／思考は「思考の詳細」、補足は実行中・出力あり・思考要約、非空思考は短文も折り畳み既定閉）を前提にする。製品の `prepare` / `summary` / 切り詰め関数から期待値を生成していない。各行はテスト内の独立リテラル。

| 検査 | 契約 |
|---|---|
| `prepare` 固定表（4区切り・部分閉じ・最外・改行境界・保護領域・CRLF・対象外） | `prepare` の有限規則と固定期待値 |
| 冪等と元入力不変、`"**確"` → `"**確認"` → `"**確認**"`、同長 `"**更新"` | 固定期待値直後のストリーミング条項 |
| `summary` 固定表（ATX 遡及・候補外・複数行インライン・コード領域・空入力） | `summary` の候補と固定期待値 |
| 60/61 `Character`（6 リテラル連結。`e\u{301}` と家族絵文字は各 1） | 60文字境界の PM 固定リテラル |
| `splitFencedCodeBlocks` / UTF-8（0/3/4空白・タブ・3/4本・チルダ・未閉じ互換例外・CRLF） | フェンス分割の固定期待値 |
| 分割後 `.markdown` を `prepare`/`summary` してもコード内部は不変 | 分割後保護 |
| `markdownBlocks` 同長別内容 | 受け入れテスト追記 |
| `AgentMessageBody(text:)` 既定 primary と `bodyColor:`、`RichMarkdownView` 通常/`streaming:` | 実 View と本文色の配線 |
| `themeCacheKey(themeID:scale:bodyColor:)` の役割分離（キー不一致を実描画と読み替えない） | テーマキャッシュキー |
| 目視: 同一画面の回答 primary と思考 secondary、同一 ID 更新、幅 360/720・倍率 0.8/1.0/2.0・明暗 | 課金なし PM 目視ゲート |
| `--selftest` 正例・負例 | Ruby 節の単一違反リスト |

task-46 の分類・コマンド表・開閉テストは同パッケージの凍結テストを恒久回帰として再実行する（本ファイルへ複製しない）。

## `xcrun swiftc -parse` 原文

作業ディレクトリはリポジトリルート。構文のみ。モジュール解決・型検査はしない（新規 API 未実装のコンパイル RED は PM が凍結時に実パスへ移して確認する）。

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceTranscriptMarkdownPresentationTests.swift
$ echo parse_acceptance_exit=0
parse_acceptance_exit=0
$ xcrun swiftc -parse tasks/frozen/staged/PMTranscriptVisualTask47Tests.swift
$ echo parse_visual_exit=0
parse_visual_exit=0
```

標準出力・標準エラーは空。終了コード 0。構文欠陥は無い。

## Ruby `--selftest` 原文

作業ディレクトリはリポジトリルート。メモリ fixture で本番検査関数を呼び、正例と負例の期待エラー集合を `==` で厳密比較する。

```
$ ruby .claude/scripts/task47-wiring.rb --selftest
task47-wiring --selftest: OK
```

終了コード 0。

正例は、契約どおりの接続、コメント/文字列/補間の追加、固定 SHA が HEAD と同じでも実装前 blob なら拒否しない、新規製品ファイルの基準不存在は git 障害ではない、scope なしでは範囲外パスを恒久 NG にしない、を含む。負例は契約が列挙した「通常入口／streaming 入口未接続」「補正結果未使用」「短文直接表示」「要約だけの本文」「secondary 転送欠落」「テーマ本文 primary 固定」「色役割のキャッシュキー欠落」「回答既定色の変更」「コードへの補正」「コピー変更」「開閉リセット」「空判定変更」「保護宣言変更」「typography 退行」「凍結 Swift・ハーネス・Ruby 改変」「基準未設定・HEAD・HEAD~1・@・ブランチ名・契約不一致・非祖先・実装済み基準・blob 取得失敗」を、期待配列との `==` で固定している。scope だけの範囲違反は `TASK47_SCOPE_CHECK=1` のみ失敗し、恒久契約違反は scope の有無にかかわらず失敗する。

本番パス（`TASK47_BASELINE` 未設定 + 契約 `baseline_commit: "PM が凍結時に設定"`）は凍結後に通す。今回は指示どおり `--selftest` と `swiftc -parse` のみ。

## 契約の曖昧点（検査側の確定）

契約・製品は変更していない。テストが採った解釈だけを残す。

1. **本文色の型**: task-46 HIGH2 の正常 fixture に合わせ、`bodyColor` は `Color`（既定 `DSColor.chatTextPrimary`、思考は `DSColor.chatTextSecondary`）。役割 enum は新設しない。
2. **補正の接続点**: 通常・`streaming:` 両 `init` が `TranscriptMarkdownPresentation.prepare` の戻り値を格納し、`body` の `Markdown(...)` がその格納値を使う。`Markdown(raw)` のように別プロパティへ逃がすと「補正結果未使用」。
3. **キャッシュキー**: 既存 `themeCacheKey(themeID:scale:)` に `bodyColor:` を足す。同じ theme ID・倍率でも primary/secondary は異なるキー。キー不一致を色の実描画確認とはしない。
4. **60文字**: 契約の 6 リテラルを連結した 60 `Character` を入力かつ期待値にする。61 は同じ 60 リテラル＋`"追"` の入力に、同じ 60 リテラル＋`"…"`（U+2026）を期待する。`prefix` や製品関数から作らない。`e\u{301}` は結合のまま（NFC しない）。家族絵文字は 1 `Character`。
5. **未閉じ3本フェンス**: `"``` json\n..."` の空白入り言語表記だけ既存互換例外。3空白字下げ・4本以上・チルダの未閉じ開始行は書き換えない。
6. **分割と UTF-8**: `ChatMarkdownBlock` の等値に加え、`.markdown`/`.code.text` の UTF-8 バイト列を比較する。コードカードのコピー対象は `.code.text` と同じリテラル。
7. **nil 要約の非空思考**: 空白 trim だけを非表示にし、`summary == nil` を非表示条件に足すと「空判定変更」。
8. **目視ハーネス**: 新規 API を参照せず既存 `ChatTranscriptView` / イベント注入 / 同一ホスト identity / `ComposerLayout.transcriptContentMaxWidth` / 専用 `UserDefaults` で再現する。受け入れテスト側が未実装 API を参照するため、実パスへ移した直後のコンパイル RED は受け入れテストが原因。
9. **`baseline_commit`**: プレースホルダのまま。rb 本番は凍結 SHA 設定後。B47 は task-46 完了（`TranscriptItemPresentation.swift` あり）と task-40 完了（`TranscriptTypography.swift` あり）を含み、`TranscriptMarkdownPresentation.swift` を含まない。

## 凍結時メモ（PM）

- テストとハーネスを実パスへ移し、未実装シンボルのコンパイル RED を確認する。
- `.claude/scripts/task47-wiring.rb` は gitignore される。凍結コミットでは `git add -f .claude/scripts/task47-wiring.rb` と実パスの Swift を同一コミットに入れる。
- そのコミット SHA を契約 `baseline_commit` と `TASK47_BASELINE` の両方に入れる。HEAD / ブランチ名は rb が拒否する。
- task-46 回帰は `TASK46_SCOPE_CHECK=0`。task-40 の着手時残余比較は回さない。
=== REPORT COMPLETE ===
