---
task: task-46
status: completed
---

task-46（UX-05a TranscriptItemPresentation）の受け入れ検査を新規作成した。製品コード・契約・台帳は未変更。コミットしていない。他担当の未コミットファイル（AgentDomain/Tests、`tasks/frozen/staged/` の他ファイル、`.claude/scripts/task51-wiring.rb`）には触っていない。

## 作成物

- `tasks/frozen/staged/AcceptanceTranscriptItemPresentationTests.swift`（実パス `macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptItemPresentationTests.swift`。先頭コメントに実パス。Swift Testing。`TranscriptItemPresentation` 未実装のコンパイル RED が正常）
- `tasks/frozen/staged/PMTranscriptVisualTask46Tests.swift`（実パス `macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask46Tests.swift`。`PHLOX_PM_VISUAL_TASK=46` で有効化、無ければ即成功。描画ホストは既存 `Harness/TranscriptTypographyRenderHarness.swift` と同じ NSHostingView 方式）
- `.claude/scripts/task46-wiring.rb`（`TASK46_BASELINE` 必須、契約 `baseline_commit` 一致、HEAD/ブランチ名拒否、祖先確認、基準に task-40 の `TranscriptTypography.swift` あり・`TranscriptItemPresentation.swift` なし、凍結テスト 2 本と rb の blob 同一性、製品配線、`--selftest`）
- `docs/agent-output/tests-task-46.md`

テストは SessionFeature 実パスに置いていない（他担当の SessionFeature テストと衝突しないよう退避）。PM が凍結時に実パスへ移す。

## 期待値の出所

正本は `tasks/task-46.md`。分類モデルや `CommandGroupHeader` の出力から期待値を生成していない。各行はテスト内の独立リテラル。実モデル `CommandGroupHeader` / `CommandGroupRowWindow` / `CommandGroupOutputDisplay` / `FileChangeDisplayPolicy` は別呼び出しで同じリテラルへ照合する。

| 検査 | 契約 |
|---|---|
| 回答の分類・折り畳み不可・本文表示 | 表示分類表、Swift Testing 表「通常・複数段落の回答」 |
| 非空思考の「思考の詳細」・詳細・既定閉（1行・複数行・61文字） | 同表、Swift Testing 表 |
| `""` / `" \t\n"` の思考は非表示 | 「空白だけの思考は非表示」 |
| 要約 `nil` でも表示、展開本文は原文 | 「非空思考、要約 nil」 |
| 同長別内容・別要約 | 「同長別内容・別要約」 |
| タスク0・1・2件の見出しと既定閉、空タスク「タスクなし」 | 表示分類表、Swift Testing 表 |
| override `nil`/`true`/`false` → 閉・開・閉 | 「導出は `userOverride ?? defaultExpanded`」 |
| マウント継続なら開閉保持、空白を挟む再表示は閉 | 「開閉と実 View への配線」 |
| 処理中は状態分類・活動ラベル、エラーは「エラー」と本文 `"a/**/b: error"` | 表示分類表 |
| 差分0・1・500・501、未操作は閉、501は初期500・残り1 | Swift Testing 表、`FileChangeDisplayPolicy.visibleLineLimit` |
| コマンド表 13 行×4 状態、`nil` command、path を件数から推測しない | 「コマンド表示の固定期待値」 |
| `[false,true]` / `[false,false]`、51件窓の固定 ID 配列 | 同節の追加固定期待値 |
| 21行出力は初期20・隠れ1・展開21・コピー全文 | 「実モデルも直接検査する」 |
| 配線・SCOPE 分離・typography 維持 | Ruby 節、task-40 注記 |

## `xcrun swiftc -parse` 原文

作業ディレクトリはリポジトリルート。構文のみ。モジュール解決・型検査はしない（`TranscriptItemPresentation` 未実装のコンパイル RED は PM が凍結時に実パスへ移して確認する）。

```
$ xcrun swiftc -parse tasks/frozen/staged/AcceptanceTranscriptItemPresentationTests.swift
```

標準出力・標準エラーは空。終了コード 0。構文欠陥は無い。

```
$ xcrun swiftc -parse tasks/frozen/staged/PMTranscriptVisualTask46Tests.swift
```

標準出力・標準エラーは空。終了コード 0。構文欠陥は無い。

## Ruby `--selftest` 原文

作業ディレクトリはリポジトリルート。メモリ fixture で本番関数を呼び、正例と負例の期待エラー集合を `==` で厳密比較する。

```
$ ruby .claude/scripts/task46-wiring.rb --selftest
task46-wiring --selftest: OK
```

終了コード 0。

正例は、配線空 NG、URL/補間/文字列内空白の保持、task-47 許可の本文・要約・色引数変更、固定 SHA が HEAD と同じでも実装前 blob なら拒否しない、`SCOPE_CHECK` 未設定/`0` では範囲外変更を範囲違反にしない、を含む。負例は契約が列挙した「モデル未接続」「短文だけ直接表示」「件数誤り」「常時展開」「更新時リセット」「実行中補足欠落」「エラー色・活動 AX・コピー・描画窓・`TranscriptTypography` の接続欠落」「コメント・if false・未使用コードによる偽装」「構文抽出失敗」「task-47 許可 fixture に開閉リセットまたは typography 退行を1件加える」「基準未設定・HEAD・`HEAD~1`・`@`・ブランチ名・契約不一致・非祖先・実装済み基準・task-40 不在・blob 取得失敗・凍結改変」「`SCOPE_CHECK=1` の範囲外変更 / AgentMessageBody 改変」を、期待配列との `==` で固定している。

本番パス（`TASK46_BASELINE` 未設定 + 契約 `baseline_commit: "PM が凍結時に設定"`）は凍結後に通す。今回は指示どおり `--selftest` のみ。

## 契約の曖昧点（検査側の確定）

契約・製品は変更していない。テストが採った解釈だけを残す。

1. **公開 API**: `struct TranscriptItemPresentation`。入れ子 `Classification`（`answer`/`detail`/`status`/`error`）、`SemanticInk`（`normal`/`process`/`error`）、`CommandPath`（`single`/`group`）。工場メソッド `answer` / `reasoning(text:summary:)` / `command(path:itemCount:isRunning:hasNonBlankOutput:)` / `fileChange(title:)` / `taskList(count:)` / `activity(label:)` / `error(message:)`。開閉は `isExpanded(userOverride:defaultExpanded:)` と `retainedUserOverride(previous:remainedMounted:)`。
2. **コマンド経路**: 件数 1 だけでは推測しない。単体の表示可否は実行中または非空白出力。グループは `CommandGroupHeader.shouldRender` と一致（実行中、または 1 件、または非空白出力あり）。
3. **補足「出力あり」**: 表示対象に空白以外の出力があるときだけ。出力中の `"error"` からは失敗を推測しない。実行中が優先。
4. **非表示行の見出し**: コマンド表の見出し文字列は表示可否に関わらず導出する。
5. **単体の展開行 ID**: 表示中なら入力 ID（`a`）、非表示なら `[]`。グループの行 ID だけ `CommandGroupRowWindow.slice` と照合する。
6. **ファイル変更見出し**: 既存要約は入力 `title` として渡す。増減件数の色分けは View 側の既存経路。
7. **PM 目視**: `PHLOX_PM_VISUAL_TASK=46` のときだけウィンドウを保持。無ければ即成功。実行状態は VM へ `.turnStarted` / `.turnCompleted(nativeSessionId: nil)` を流し `status.isRunning` を待つ。幅は `ComposerLayout.transcriptContentMaxWidth`、末尾余白はコンポーザ計測高さ。
8. **恒久回帰と SCOPE**: 恒久は分類モデル接続・短文直接表示拒否・定数 Binding 拒否・typography 経路。`TASK46_SCOPE_CHECK=1` のときだけ許可パス外と `AgentMessageBody` / 描画窓 / コピー正本の基準比較を行う。task-47 の本文 Markdown・要約式・色引数は恒久で許容する。
9. **`baseline_commit`**: プレースホルダのまま。rb 本番は凍結 SHA 設定後。

## 凍結時メモ（PM）

- テスト 2 本を契約 `acceptance_tests` の実パスへ移し、未実装コンパイル RED を確認する。
- `.claude/scripts/task46-wiring.rb` は gitignore される。凍結コミットでは `git add -f .claude/scripts/task46-wiring.rb` と実パスのテストを同一コミットに入れる。
- そのコミット SHA を契約 `baseline_commit` と `TASK46_BASELINE` の両方に入れる。HEAD / ブランチ名は rb が拒否する。基準に `TranscriptTypography.swift` があり `TranscriptItemPresentation.swift` が無いことを rb が確認する。

=== REPORT COMPLETE ===
