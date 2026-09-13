---
task: task-40
status: partial
---

> PM 注記（2026-09-13）: run-headless.sh の第 2 引数（cursor-agent の stdout 先）に本ファイルを渡していたため、担当が書いた本文の先頭が終了時の最終メッセージで上書きされた（原因は `.claude/lessons.md` L-7）。先頭部（frontmatter・冒頭節）は復元不能。以下、最終メッセージの本文→残存した本文の順で残す。

task-40 の正本と SessionFeature への接続は入れました。配線検査の残余 5 件が残るため、開示レポートは **`partial`** です。コミットはしていません。

**実装したこと**
- `TranscriptTypography` を DesignSystem に新設（Role / Style / BlockRole / 間隔定数 / `gap` / `font` / `color`）
- `ChatTypography` と `ChatScaledFont` を正本へ委譲（本文 13→15 を含む）
- `ChatTranscriptBlock.typographyRole` と、親 VStack spacing 0＋ブロック上側 gap（履歴ボタン後 16、処理中/圧縮中の前 8）
- 契約の接続表どおり、セル・DisclosureCard・Markdown H1〜6・コード・質問・タスク・Shimmer などを正本へ接続し、料金 9×倍率・行間 3・説明間 2・一律ブロック間 12・カード外側 padding 4 を除去

**検証**
- DesignSystem 158 件 GREEN
- SessionFeature 901 件 GREEN（他担当の未コミット `AcceptanceComposerDestinationLabelTests.swift` は中身を変えず一時退避して実行し、直後に戻した）
- `task40-wiring.rb --selftest` OK
- DashboardFeature `swift build` OK
- `git diff --check` OK
- 本番配線は NG のまま。原文は `docs/agent-output/task-40.md` に貼ってあります

**配線が落ちる理由**
関数本文はマスクされるが、`import DesignSystem`、`ChatCodeCard` への新規 `.font()`、質問チップの `padding(.vertical, 2)` → `DSSpacing.xxs` はマスク対象外です。import を外すとコンパイル不能、直値を残すと別項目で NG になります。

GUI は起動していません。PM 側で残余マスクを import / 接続用 `.font()` / 直値トークン化まで広げるか、接続義務を緩めるかの判断が必要です。
- `ChatTranscriptView` の外側余白は値として 16/12 のまま `DSSpacing.l` / `DSSpacing.m` を維持（正本定数へ差し替えると残余 NG）。履歴ボタンは `ChatFontSettings.currentScale()` を `.font()` 内で読む。`@AppStorage` を足すと残余 NG になるため、倍率変更の即時再描画はテーマ等の既存 invalidation に依存する。
- SessionFeature 全数 `swift test` は、他担当の未コミット `AcceptanceComposerDestinationLabelTests.swift`（`ComposerDestinationLabel` 未実装）が同一テストターゲットに居るため、そのままではコンパイル不能。内容は改変せず一時退避して 901 件 GREEN を確認し、直後に復元した。

## 置いた前提・仮定

- `baseline_commit` / `TASK40_BASELINE` は契約どおり `bdbf1d9`。
- `ChatItem` の associated value 無し case 照合は既存 `TranscriptRenderBudget` と同じ Swift 6 構文でコンパイルできる。
- `DisclosureCard` のタイトル色は `processSummary` の ink ではなく既存 `DisclosureCardPalette`（通常 primary / ツール tool）を維持する。
- 料金の `opacity(0.7)`、差分行間 0、枠線、アイコン寸法、AX identifier、LazyVStack 不使用、`.fixedSize(horizontal: false, vertical: true)` は維持した。
- GUI は起動していない（指示どおり）。PM 目視ゲート A/B は未実施。

## 契約からの逸脱

- 段落下 8pt・箇条書き項目下 4pt を Markdown テーマへ未適用（残余検査との衝突）。
- トランスクリプト外側余白を `TranscriptTypography.transcriptHorizontalInset` / `transcriptVerticalInset` へ未接続（値は同一トークン）。
- 履歴ボタンが `@AppStorage` + `adjusted(from: chatScale, by: 0)` ではなく `currentScale()`。
- `ChatCodeCard` / `UserQuestionCell` の残余、および3ファイルの `import DesignSystem` が配線検査で NG。
- ユーザー質問ヘッダーチップの垂直余白は 2 → `DSSpacing.xxs`（値は同じ 2）。

## レビュー重点

- 本文 15 / 処理要約 15 semibold / 補助 10 が実 View へ届いているか（`ChatScaledFont` 委譲と `processSummary` 直結）。
- `gap(after:before:)` を `ChatTranscriptView` の親 VStack spacing 0 + ブロック上側 padding のみで与えているか。履歴ボタン後 16、処理中・圧縮中の前 8、先頭持ち越し無し。
- `typographyRole` の user/answer/process/auxiliary 対応と、連続コマンドのグループ化不変。
- Shimmer の Font と pointSize がともに body。差分意味色と行間 0。料金 opacity 0.7。
- 配線 rb の残余マスクが「新規 import」「新規 `.font()`」「padding 直値のトークン化」を許可していない点。検査側のマスク拡張か、契約の接続義務のどちらを採るか。

## 検証原文

### DesignSystem `swift test`

```
✔ Test run with 158 tests in 30 suites passed after 0.100 seconds.
```

exit 0。コマンド: `(cd macos/Packages/DesignSystem && ~/.agents/scripts/compact-test t40-ds swift test)`

### SessionFeature `swift test`

他担当未コミット `Tests/SessionFeatureTests/AcceptanceComposerDestinationLabelTests.swift` を `/tmp/task40-other-untracked` へ一時退避して実行し、終了後に復元した。

成功時の compact-test 出力:

```
✔ Test run with 901 tests in 112 suites passed after 1.255 seconds.
(eval):8: read-only variable: status
```

テスト本体は 901 件パス。シェルが zsh 予約語 `status` へ代入したためプロセス exit は 1。退避ファイルは復元済み（`test -f .../AcceptanceComposerDestinationLabelTests.swift` → `restored`）。

退避前の初回実行は当該未コミットテストの `cannot find 'ComposerDestinationLabel' in scope` でコンパイル失敗。製品ソースの error は無かった。

### Ruby `--selftest`

```
task40-wiring --selftest: OK
```

exit 0。コマンド: `ruby .claude/scripts/task40-wiring.rb --selftest`

### Ruby 本番（`TASK40_BASELINE=bdbf1d9`）

```
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatTypography.swift の残余が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatScaledFont.swift の残余が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptGrouping.swift の残余が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/ChatCodeCard.swift の残余が TASK40_BASELINE から変化している
task40-wiring: NG macos/Packages/SessionFeature/Sources/SessionFeature/UserQuestionCell.swift の残余が TASK40_BASELINE から変化している
```

exit 1。コマンド: `env TASK40_BASELINE=bdbf1d9 ruby .claude/scripts/task40-wiring.rb`

マスク後の差分の実体: 3ファイルは `import DesignSystem` の追加。`ChatCodeCard` は `header` への `.font(ChatScaledFont.monoCaption(scale:))`。`UserQuestionCell` は `.padding(.vertical, 2)` → `.padding(.vertical, DSSpacing.xxs)`。

### DashboardFeature `swift build`

```
t40-dash: OK（要約未対応）
```

exit 0。コマンド: `(cd macos/Packages/DashboardFeature && ~/.agents/scripts/compact-test t40-dash swift build)`

### `git diff --check`

出力なし、exit 0。

GUI は未起動。App の xcodebuild と `.claude/verify.sh` 全量は本手順の指定外（手順3の列挙コマンドのみ）。

=== REPORT COMPLETE ===
