受け入れ検査 3 点を新規作成し、製品コード・契約・台帳は触っていません。コミットもしていません。

**作成したファイル**
- `macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceTranscriptTypographyTests.swift` — Role 表・pointSize×倍率・順序不等式・間隔・gap 20 条件を独立リテラルで固定
- `macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptTypographyIntegrationTests.swift` — `typographyRole`、連続コマンド 1 グループ、gap `[0, 16, 8, 8, 16, 8, 24]`、途中開始で 24 を持ち越さない、委譲。描画は含めていない
- `.claude/scripts/task40-wiring.rb` — `TASK40_BASELINE`・凍結 blob・View 接続・旧直値・`--selftest`

**確認結果**
- `ruby .claude/scripts/task40-wiring.rb --selftest` → `task40-wiring --selftest: OK`（exit 0）
- DesignSystem / SessionFeature の `swift build --build-tests` はコンパイル RED。原因は `TranscriptTypography` 未定義と `typographyRole` 未追加のみ（構文エラーや ChatItem 誤用ではない）

報告は `docs/agent-output/tests-task-40.md` にあります。凍結時は `.claude/scripts/task40-wiring.rb` を `git add -f` し、`baseline_commit` を実 SHA に置き換えてください。
否しない。製品検査は契約「2.」の 7〜14 |

`.claude/` は `.gitignore` されている。凍結コミット時は `git add -f .claude/scripts/task40-wiring.rb` が必要。

## 期待値の出所（契約の行）

| 検査 | 契約 |
|---|---|
| Role 表（基準 pt / weight / design / ink） | `tasks/task-40.md` 108–123 |
| ink → DSColor | 同 125 |
| 既存窓口の委譲（`ChatTypography` / `ChatScaledFont`） | 同 137–143 |
| 間隔定数（8 / 16 / 24 / 4…） | 同 151–162 |
| `gap` 20 条件 | 同 179–187 |
| `typographyRole` 対応表 | 同 193–199 |
| Swift Testing 項目（独立リテラル・倍率・不等式・20 条件） | 同 244–255 |
| 統合（role 対応・1 グループ・`[0, 16, 8, 8, 16, 8, 24]`・途中開始・委譲） | 同 257–264 |
| 描画ハーネスを凍結から外す | 同 400–401（PM 採択時の調整） |
| 配線検査 1–14 と `--selftest` | 同 274–294 |
| 残余 blob 比較は `allowed_paths` の製品ファイルに限定 | 同 402 |

## RED 原文

### DesignSystem（`TranscriptTypography` 未定義）

```sh
(cd macos/Packages/DesignSystem && ~/.agents/scripts/compact-test t40-red swift build --build-tests)
```

exit 1。構文エラーは無し。`CGFloat` 未 import も無し。代表行:

```
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceTranscriptTypographyTests.swift:16:40: error: cannot find type 'TranscriptTypography' in scope
 14 | struct AcceptanceTranscriptTypographyTests {
 15 |     /// 契約「文字の正本」Role 表。実装の `allCases` から作らない。
 16 |     private static let expectedRoles: [TranscriptTypography.Role] = [
    |                                        `- error: cannot find type 'TranscriptTypography' in scope
```

```
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceTranscriptTypographyTests.swift:22:45: error: cannot find type 'TranscriptTypography' in scope
 22 |     private static let expectedBaseSizes: [(TranscriptTypography.Role, CGFloat)] = [
    |                                             `- error: cannot find type 'TranscriptTypography' in scope
```

同一ファイルの後続は `cannot find 'TranscriptTypography' in scope` と、型が無いためのカスケード（`cannot infer contextual base in reference to member 'body'` / `'regular'` / `'system'` 等、`member 'bold' expects argument of type 'Never'`）。別型の誤用・構文エラーではない。

### SessionFeature（`TranscriptTypography` 未定義 + `typographyRole` 未追加）

```sh
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-sf-red swift build --build-tests)
```

exit 1。`ChatItem` / `ChatTranscriptBlock` のイニシャライザ誤用は無し。代表行:

```
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptTypographyIntegrationTests.swift:40:19: error: cannot find type 'TranscriptTypography' in scope
 39 | private func gaps(for blocks: [ChatTranscriptBlock]) -> [CGFloat] {
 40 |     var previous: TranscriptTypography.BlockRole?
    |                   `- error: cannot find type 'TranscriptTypography' in scope
```

```
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptTypographyIntegrationTests.swift:42:26: error: value of type 'ChatTranscriptBlock' has no member 'typographyRole'
 41 |     return blocks.map { block in
 42 |         let role = block.typographyRole
    |                          `- error: value of type 'ChatTranscriptBlock' has no member 'typographyRole'
```

```
/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptTypographyIntegrationTests.swift:53:66: error: value of type 'ChatTranscriptBlock' has no member 'typographyRole'
 53 |         #expect(ChatTranscriptBlock.single(typographyUser("u1")).typographyRole == .user)
    |                                                                  `- error: value of type 'ChatTranscriptBlock' has no member 'typographyRole'
```

後続の `cannot infer contextual base` は上記 2 種の未定義からのカスケード。

## selftest 結果原文

```sh
ruby .claude/scripts/task40-wiring.rb --selftest
```

```
task40-wiring --selftest: OK
```

exit 0。

## PM が凍結時に行うコマンド

1. 本 3 ファイルを凍結コミットに含める（`.claude/scripts/task40-wiring.rb` は `git add -f`）。
2. `tasks/task-40.md` の `baseline_commit` をそのコミット SHA に置換する。
3. 未実装のまま RED と `--selftest` を再確認する。

```sh
~/.agents/scripts/compact-test task40-wiring-selftest ruby .claude/scripts/task40-wiring.rb --selftest
(cd macos/Packages/DesignSystem && ~/.agents/scripts/compact-test t40-red swift build --build-tests)
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-sf-red swift build --build-tests)
~/.agents/scripts/compact-test task40-wiring env TASK40_BASELINE=<固定SHA> ruby .claude/scripts/task40-wiring.rb
```

4. 実装後ゲート（契約「3.」）。`<固定SHA>` と DerivedData パスは凍結実値へ置換する。

```sh
~/.agents/scripts/compact-test task40-packages bash macos/scripts/run-swift-tests.sh DesignSystem SessionFeature DashboardFeature
~/.agents/scripts/compact-test task40-wiring env TASK40_BASELINE=<固定SHA> ruby .claude/scripts/task40-wiring.rb
~/.agents/scripts/compact-test task40-integration bash .claude/verify.sh
~/.agents/scripts/compact-test task40-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用DerivedData絶対パス> -destination platform=macOS build
```

5. `task40-wiring.rb` を `.claude/verify.sh` へ接続する（契約どおり、凍結時に PM が行う）。
6. 目視ゲート B の描画ハーネス（`TranscriptTypographyRenderHarness.swift` 等）は凍結対象外・PM 所有。

## 未対応事項

- 成功基準 3 のパッケージテスト・App ビルド・`verify.sh` 統合は未実行（凍結後・実装後のゲート）。
- 成功基準 4 の PM 目視（隔離 Debug / fixture 描画）は未実施。NSHostingView / ImageRenderer は凍結テストに入れていない。
- `baseline_commit` はプレースホルダのまま。本番 `TASK40_BASELINE` 検査は凍結 SHA 設定後。
- `verify.sh` への Ruby 検査接続は未実施（契約: PM が凍結時に接続）。

=== REPORT COMPLETE ===
