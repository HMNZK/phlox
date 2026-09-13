---
task: task-43
status: completed
---

> PM 注記（2026-09-13）: run-headless.sh の第 2 引数（cursor-agent の stdout 先）に本ファイルを渡していたため、担当が書いた本文の先頭が終了時の最終メッセージで上書きされた（原因は `.claude/lessons.md` L-7）。先頭部（frontmatter・冒頭節）は復元不能。以下、最終メッセージの本文→残存した本文の順で残す。

task-43 の受け入れ検査を新規作成し、未実装 RED と `--selftest` を原文で確認した。製品コード・契約・台帳は未変更。コミットしていない。

作成したのは次の 3 点と報告である。

- `macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceComposerDestinationLabelTests.swift`
- `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/AcceptanceTeamComposerDestinationLabelTests.swift`
- `.claude/scripts/task43-wiring.rb`
- `docs/agent-output/tests-task-43.md`（1 行目 `---`、`status: completed`、末尾 `=== REPORT COMPLETE ===`）

期待値は契約 `tasks/task-43.md` のリテラル（基本文言、送信不可の優先順、phase 表 12 件、選択カードと根の差）から書いた。Dashboard 側は `AgoraComposerRouting.action` と `TeamComposerTarget.resolveRootSessionID` を実際に呼んでいる。

`ruby .claude/scripts/task43-wiring.rb --selftest` は `task43-wiring --selftest: OK`（exit 0）。

`swift build --build-tests` は SessionFeature・DashboardFeature とも exit 1。error はすべて今回の受け入れテスト内の `cannot find 'ComposerDestinationLabel' in scope` と、それに追随する型推論カスケードだけ。既存テストや製品ソースの error はない。

凍結時は `.claude/` が gitignore されるので `git add -f .claude/scripts/task43-wiring.rb` が必要。契約の `baseline_commit` はまだプレースホルダのまま。他担当の SessionFeature / DesignSystem 差分には触っていない。
| 欠損名 | 同節の trim / 不明規則 | プロジェクト名 nil・空・空白・改行 → `プロジェクト名不明`。作業名空白のみ → `作業名不明`。日英・内部空白は保持 |
| 送信不可 優先順 | 同節の付加表 | 送信先なし → 入力不可 → 本文なし。3 Bool × 4 Destination の 8 組 |
| 添付あり | 成功基準 1.7 / View 配線 `hasContent` | `hasContent == true` では本文未入力理由を付けない |
| `.starting` / `.error` | 確認した既存経路 / 成功基準 1.8 | `isReadyForInput == false` だけが入力不可理由。復元エラーを独自禁止しない |
| 単一・グリッド・チーム × 開始前/進行中/終了後/開始不可 | 成功基準 1 とユーザー指示 | 単一/グリッドは `conversation` のまま討論状態に影響されない。チーム開始前 `討論を開始`、進行中 `討論への発言`、終了後かつ開始可能は親送信に固定しない、開始不可は親送信（送信不可理由は自動で付けない） |
| 選択カード ≠ 送信先 | View 配線 / 成功基準 1 Dashboard | 子 `Garden / 子の調査`、親送信は根 `Phlox / 全体作業 — 親セッションへの送信` |
| 討論分岐の合成 | 「純粋モデル：既存の討論分岐との接続」+ 成功基準 1 の phase 表 12 件 | 実 `AgoraComposerRouting.action` → `teamDestination` → `text`。モックなし |
| 配線 | 成功基準 2 の必須検査すべて | 単一/グリッド/チームの Text 到達、既定 nil/空辞書拒否、`projectID`、選択カード名拒否、`sendTeamMessage` と同じ phase/開始可否、宛先なしでも表示、AX/help、編集領域直前、計測範囲、画像のみを送信不可にしない、討論開始でボタン有効化しない、不変関数の宣言比較 |

`ComposerDestinationLabel` は未実装。SessionFeature テストは `@testable import SessionFeature`。Dashboard 合成は `import SessionFeature` + `@testable import DashboardFeature`（契約スニペットの `teamDestination` は `static` のみで `public` ではない）。

## Ruby `--selftest` 原文

作業ディレクトリはリポジトリルート。メモリ fixture で本番関数を呼び、正例と負例の期待エラー集合を厳密比較する。

```
$ ruby .claude/scripts/task43-wiring.rb --selftest
task43-wiring --selftest: OK
```

終了コード 0。

正例には、配線空 NG、URL/補間/文字列内空白の保持、固定 SHA が HEAD と同じでも実装前 blob なら拒否しない、を含む。負例は契約が列挙した「単一だけ未接続」「グリッドだけ選択中カード名」「親名を子名に差替え」「終了後を親送信に固定」「`.concluding` を討論外扱い」「討論開始可能でボタン有効化」「画像のみを送信不可」「help のみ」「AX 欠落」「宛先なしで非表示」「submit / 送信先 / disabled / 編集可否の変更」「コメント・未使用コードによる偽装」「構文抽出失敗」「基準未設定・HEAD・`@`・ブランチ名・契約不一致・実装後自己比較」を、期待配列との `==` で固定している。

本番パス（`TASK43_BASELINE` 未設定 + 契約 `baseline_commit: "PM が凍結時に設定"`）は凍結後に通す。今回は指示どおり `--selftest` のみ。

## Swift RED 原文（未定義シンボル由来のみ）

両パッケージとも作業ディレクトリをパッケージ直下にし、`swift build --build-tests` を実行した。終了コードはいずれも 1。診断ファイルはすべて今回の受け入れテスト。製品ソースの error は無い。カスケード（`.conversation` 等の型推論、`'nil' requires a contextual type`）は `ComposerDestinationLabel` 未定義に追随する。テスト自身の構文欠陥・既存テストの error は無い。

### SessionFeature

```
$ (cd macos/Packages/SessionFeature && swift build --build-tests)
Building for debugging...
[4/7] Emitting module SessionFeatureTests
[5/7] Compiling SessionFeatureTests AcceptanceComposerDestinationLabelTests.swift
.../AcceptanceComposerDestinationLabelTests.swift:26:13: error: cannot find 'ComposerDestinationLabel' in scope
 24 |     func conversationPhloxExactMatch() {
 25 |         #expect(
 26 |             ComposerDestinationLabel.text(
    |             `- error: cannot find 'ComposerDestinationLabel' in scope
 27 |                 for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
...
.../AcceptanceComposerDestinationLabelTests.swift:27:23: error: cannot infer contextual base in reference to member 'conversation'
EXIT:1
```

error 内訳（`: error:` 行）: `cannot find 'ComposerDestinationLabel' in scope` 46、`cannot infer contextual base` 46、`'nil' requires a contextual type` 4。ファイルは `AcceptanceComposerDestinationLabelTests.swift` のみ（96）。

### DashboardFeature

```
$ (cd macos/Packages/DashboardFeature && swift build --build-tests)
[6/8] Compiling DashboardFeatureTests AcceptanceTeamComposerDestinationLabelTests.swift
.../AcceptanceTeamComposerDestinationLabelTests.swift:36:27: error: cannot find 'ComposerDestinationLabel' in scope
 34 |             text: actionText
 35 |         )
 36 |         let destination = ComposerDestinationLabel.teamDestination(
    |                           `- error: cannot find 'ComposerDestinationLabel' in scope
 37 |             action: action,
 38 |             rootProjectName: rootProjectName,
...
.../AcceptanceTeamComposerDestinationLabelTests.swift:41:16: error: cannot find 'ComposerDestinationLabel' in scope
 41 |         return ComposerDestinationLabel.text(
EXIT:1
```

既存テスト（例: `AcceptanceSubAgentDismissTests.swift`、`AcceptancePaneLayoutPresetMenuTests.swift`）は warning のみ。error は `AcceptanceTeamComposerDestinationLabelTests.swift` に限る。`.startDiscussion` / `.discussionUtterance` / `.legacyRootSend` の `cannot infer contextual base` は、未知の `teamDestination` 引数型からのカスケードであり、`AgoraComposerAction` 自体の欠落ではない（`[AgoraComposerAction]` 配列と `AgoraComposerRouting.action` は解決している）。

## 契約の曖昧点（検査側の確定）

契約・製品は変更していない。テストが採った解釈だけを残す。

1. **親の「作業名なし」**: 基本文言表は `親セッションへの送信`。conversation の欠損規則（`作業名不明`）とは別。テストは表を正とした（nil / 空 / 空白のみ）。
2. **`teamDestination` の可視性**: 契約スニペットは `static func` のみ。Dashboard テストは `@testable` 前提。公開にするかは実装の裁量で、テストは契約スニペットに合わせた。
3. **循環 resolver**: 契約は「既存 resolver の返り値を使い、新しい探索規則を定義しない」。返りノードは a/b どちらでもよい既存仕様に合わせ、`Phlox / 循環A — 親セッションへの送信` または `Garden / 循環B — 親セッションへの送信` の OR。
4. **単一/グリッドの討論状態**: 契約どおり同一 `conversation` モデル。討論 phase を単一/グリッドの製品経路へ通す分岐は無い。Session 側はモデルリテラル、Dashboard 側は実 `action` 合成で phase 表を凍結した。
5. **`baseline_commit`**: プレースホルダのまま。rb 本番（祖先確認・blob 同一性・製品配線）は凍結 SHA 設定後。`--selftest` のメモリ fixture は、HEAD と同じ SHA でも実装前 blob なら合格することを正例にしている。
6. **開始不可 ≠ 送信不可**: チーム開始不可は親送信の基本文言であり、Bool 3 つが満たされていれば送信不可理由を付けない。

## 凍結時メモ（PM）

- `.claude/scripts/task43-wiring.rb` は gitignore される。凍結コミットでは `git add -f .claude/scripts/task43-wiring.rb` とテスト 2 ファイルを同一コミットに入れる。
- そのコミット SHA を契約 `baseline_commit` と環境変数 `TASK43_BASELINE` の両方に入れる。HEAD / ブランチ名は rb が拒否する。
- 凍結後に未実装 RED と `ruby .claude/scripts/task43-wiring.rb --selftest` を再確認する。製品配線の本番 rb は実装後。

=== REPORT COMPLETE ===
