---
task: task-49
status: completed
---

# task-49 受け入れ検査 敵対レビュー反映

対象は退避先のまま編集した。実パスへコピー・移動していない。製品コード・契約・台帳は変更していない。

## 指摘ごとの反映

### MUST1（class 解析、比較元・比較先欠落は非ゼロ）
- `.claude/scripts/task49-wiring.rb:191` `extract_type_body` が `struct`/`class` と複数修飾子（`public final class`）を解析する。
- 同ファイル `1026` 行: `protected_member_errors` は比較元・比較先欠落で非ゼロ。
- 同ファイル `1282` 行: 正例 `good_vm` を実コードどおり `public final class ChatSessionViewModel` にした。

### HIGH2（View 凍結比較と条件・高さ・余白・composer の単一違反負例）
- 実経路: `ChatSessionView.swift` overlay の `shouldOfferHistoryStart`、`ChatHistoryStartLayout.maxCardHeight(availableHeight:composerHeight:)`、`.padding(.bottom, bottomInset)`、`.overlay(alignment: .bottom)` の `ChatComposer`。
- `task49-wiring.rb:944` `check_session_view`、`1050` `session_view_freeze_errors`（`workingDirectory` 引数だけ除外）、`1059` `history_view_freeze_errors`（`frame(maxHeight:maxCardHeight)`）。
- 負例: `1652` `|| true`、`1656` 固定高さ、`1665` availableHeight 固定、`1670` View 引数固定、`1677` bottomInset 削除、`1683` composer overlay 外れ。

### HIGH3（ForEach 要素→行→モデル→Button→再開の同値）
- 実経路: `ChatHistoryStartView.swift:31` `ForEach(entries) { entry in row(for: entry) }`、`62` `row(for:)`、`64` `onSelect(entry)`、`ChatSessionView.swift:158-159` `startFromHistory(entry)`。
- `task49-wiring.rb:862` `check_history_view`（`910` 行以降の ident 照合）。
- 負例: `1688` `entries[0]`、`1691` モデルへ別 entry、`1696` 重複 onSelect、`1701` `.onAppear`、`1709` `Button` 撤去。

### HIGH4（補助表示・help・AX・案内の実接続）
- `task49-wiring.rb:517` `live_help_args` / `live_ax_label_args`（文字列リテラルを参照と数えない）。
- 同ファイル `895` `Text(presentation.projectName)`、`lastUsedAt` 受け渡し、`Text("最終利用")`、案内は `Text` リテラル。
- 負例: `1716` 固定名、`1719` `formattedLastUsed(nil)`、`1724` help 文字列偽装、`1729` 案内を AX へ移動。

### HIGH5（導出結果の代入と UserDefaults.standard / Date.now 拒否）
- `task49-wiring.rb:467` `derived_title_returned?` は `title=`/`fullTitle=` が導出結果の `.title`/`.fullTitle` であること。
- 同ファイル `604` `forbidden_presentation_deps?` に `UserDefaults` と `Date.now`。
- 負例: `1736` 別値代入、`1739` `UserDefaults.standard`、`1744` `Date.now`。

### HIGH6（材料優先・summary・未加工引き渡しのリテラル）
`tasks/frozen/staged/AcceptanceHistoryEntryPresentationTests.swift`
- `136` 適格ユーザー材料が複数なら最初
- `183` `[]` + 適格 summary
- `229` nil + 不適格 preview + 適格 summary
- `243` summary 内コマンド・改行
- `255` summary 長文 33 Character
- `268` 先頭 4 空白・タブを導出器へ渡し「説明」を採らない

導出器は `SessionTitleDeriver.swift:113-115` で 4 空白/タブ行を貼り付けコードとして飛ばす。全体 trim すると「説明」になる。

### MED7（変更範囲はリポジトリ全体）
- `task49-wiring.rb:646` `ALLOWED_SCOPE_PATHS`、`1086` `extra_changed_product_paths` は path 限定なしの `git diff --name-only`。

### MED8（公開 API）
- テスト `8` 行: `import SessionFeature`（`@testable` を外した）。
- テスト `404` 行: 非 Optional `String` と `Sendable` のコンパイル検査。
- `task49-wiring.rb:484` `presentation_public_api_errors`。負例 `1752` Sendable 欠落、`1756` `title: String?`。

### MED9（記録）
- テスト `438` 行コメント: 値不変は契約指定の確認として残し、副作用保護の証拠には数えない。副作用は HIGH5。

## selftest 原文

```
task49-wiring --selftest: OK
```

exit 0。コマンド: `ruby .claude/scripts/task49-wiring.rb --selftest`

## parse 原文

`xcrun swiftc -parse tasks/frozen/staged/AcceptanceHistoryEntryPresentationTests.swift`

標準出力・標準エラーなし。`parse_exit=0`。

## 見送った点と理由

- ChatHistoryStartView の行本文・見出し文字列は実装で変わるため、凍結比較は高さ frame の存在照合に限定した。行の接続は HIGH3/HIGH4 の到達検査で見る。
- Swift は構文 parse のみ。モデル未実装のコンパイルは PM 再凍結時。
- 製品コード・契約・台帳、他タスクの未コミットファイル、実パスへのコピーはしていない。
=== REPORT COMPLETE ===