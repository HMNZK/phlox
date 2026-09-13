---
task: task-40
status: partial
gate: B
commit: 5c6bade18b76ef26accecf42e638fb984756d407
branch: feature/ui-ux-improvement-backlog
harness: macos/Packages/SessionFeature/Tests/SessionFeatureTests/Harness/TranscriptTypographyRenderHarness.swift
png_dir: /tmp/phlox-t13-visual.SPfR9c/t40-gateB/
---

# task-40 PM目視ゲート B（SessionFeature fixture）

合否は PM が PNG を見て判定する。本ファイルはハーネス作成・実行の記録であり、読順・欠け・重なりの合格を宣言しない。

## fixture の構成

実 `ChatTranscriptView` に `transcript:` で固定 ChatItem を渡した。ViewModel は `DisconnectedHarnessClient`（`events` 即 finish、start/turnStart/resume/interrupt/close は no-op）。`startNew` は呼ばない。課金セッションは作っていない。

ホスト引数は製品 `ChatSessionView.mainColumn(width:)` と同じく `contentMaxWidth: ComposerLayout.transcriptContentMaxWidth(mainColumnWidth:)` と `bottomScrollContentMargin:`（実測した `ChatComposer` 高。360/720 とも 118pt）。

並び（8/16/24 境界を同時に置く）:

1. ユーザー u1
2. 回答 a1: 日本語長文2段落、H1〜H6、長い節見出し、長い箇条書き・番号付き・入れ子、インラインコード、表、Swift フェンス、長いコード行
3. 回答 a2: 分割出力（answer→answer の 8pt）
4. 連続コマンド 2 件（複数行 `git log` + 25行出力）。既定折りたたみ
5. Reasoning（グループ区切り）
6. 別コマンド 1 件（`rg`）
7. Reasoning（空出力グループを独立させる区切り）
8. 空出力コマンド 2 件（grouping 上は 1 グループ。`CommandGroupHeader.shouldRender=false` のためカードは出ない）
9. 差分（既定折りたたみ）
10. タスク pending / inProgress / completed
11. 質問 回答済み
12. 質問 期限切れ
13. 回答 a3（process→answer の 16pt）
14. 料金（時刻は各セルの timestamp）
15. ユーザー u2（auxiliary→user の 24pt）

幅 360/720、倍率 0.8/1.0/2.0、テーマ phlox-light と dracula。PNG は 2x バック。固定 420pt では切っていない。

## 設定保存先の確認結果

製品 `ChatTranscriptView`（および各セル）の倍率・テーマは `@AppStorage(ChatFontSettings.scaleKey)` / `@AppStorage(ThemeStore.themeKey)` で、`store:` 引数なし。SwiftUI 既定は `UserDefaults.standard`。`.defaultAppStorage(suite)` を付けたときだけテスト用 suite を読む。

`ChatFontSettings.save` / `currentScale` の既定引数は `UserDefaults.standard`。ハーネスは suite へ `ChatFontSettings.save` し、ホストに `.defaultAppStorage(suite)` を付けた。

`DSColor` は `ThemeStore.active` を読む。`ThemeStore.active` は `UserDefaults.standard` 固定。テーマ色を変えるには suite だけでは足りず、standard の `phlox.theme` を一時書込して終了時に戻した。

実行時 sidecar: `/tmp/phlox-t13-visual.SPfR9c/t40-gateB/settings-store.txt`

中点画素の実測: phlox-light `(240,240,240)`、dracula `(49,49,49)`。テーマ差は出ている。

## PNG 一覧

パスはすべて `/tmp/phlox-t13-visual.SPfR9c/t40-gateB/` 配下。寸法は pixelWidth x pixelHeight（2x）。expanded と collapsed は同一バイト（展開操作が効いていない）。

| ファイル | 寸法 | 幅pt | 倍率 | テーマ | 展開 |
| --- | --- | ---: | ---: | --- | --- |
| transcript-w360-s0.8-phlox-light-collapsed.png | 720x4122 | 360 | 0.8 | phlox-light | collapsed |
| transcript-w360-s0.8-phlox-light-expanded.png | 720x4122 | 360 | 0.8 | phlox-light | expanded（未達） |
| transcript-w360-s0.8-dracula-collapsed.png | 720x4122 | 360 | 0.8 | dracula | collapsed |
| transcript-w360-s0.8-dracula-expanded.png | 720x4122 | 360 | 0.8 | dracula | expanded（未達） |
| transcript-w360-s1.0-phlox-light-collapsed.png | 720x5383 | 360 | 1.0 | phlox-light | collapsed |
| transcript-w360-s1.0-phlox-light-expanded.png | 720x5383 | 360 | 1.0 | phlox-light | expanded（未達） |
| transcript-w360-s1.0-dracula-collapsed.png | 720x5383 | 360 | 1.0 | dracula | collapsed |
| transcript-w360-s1.0-dracula-expanded.png | 720x5383 | 360 | 1.0 | dracula | expanded（未達） |
| transcript-w360-s2.0-phlox-light-collapsed.png | 720x14028 | 360 | 2.0 | phlox-light | collapsed |
| transcript-w360-s2.0-phlox-light-expanded.png | 720x14028 | 360 | 2.0 | phlox-light | expanded（未達） |
| transcript-w360-s2.0-dracula-collapsed.png | 720x14028 | 360 | 2.0 | dracula | collapsed |
| transcript-w360-s2.0-dracula-expanded.png | 720x14028 | 360 | 2.0 | dracula | expanded（未達） |
| transcript-w720-s0.8-phlox-light-collapsed.png | 1440x3424 | 720 | 0.8 | phlox-light | collapsed |
| transcript-w720-s0.8-phlox-light-expanded.png | 1440x3424 | 720 | 0.8 | phlox-light | expanded（未達） |
| transcript-w720-s0.8-dracula-collapsed.png | 1440x3424 | 720 | 0.8 | dracula | collapsed |
| transcript-w720-s0.8-dracula-expanded.png | 1440x3424 | 720 | 0.8 | dracula | expanded（未達） |
| transcript-w720-s1.0-phlox-light-collapsed.png | 1440x4071 | 720 | 1.0 | phlox-light | collapsed |
| transcript-w720-s1.0-phlox-light-expanded.png | 1440x4071 | 720 | 1.0 | phlox-light | expanded（未達） |
| transcript-w720-s1.0-dracula-collapsed.png | 1440x4071 | 720 | 1.0 | dracula | collapsed |
| transcript-w720-s1.0-dracula-expanded.png | 1440x4071 | 720 | 1.0 | dracula | expanded（未達） |
| transcript-w720-s2.0-phlox-light-collapsed.png | 1440x7844 | 720 | 2.0 | phlox-light | collapsed |
| transcript-w720-s2.0-phlox-light-expanded.png | 1440x7844 | 720 | 2.0 | phlox-light | expanded（未達） |
| transcript-w720-s2.0-dracula-collapsed.png | 1440x7844 | 720 | 2.0 | dracula | collapsed |
| transcript-w720-s2.0-dracula-expanded.png | 1440x7844 | 720 | 2.0 | dracula | expanded（未達） |
| cell-user-w720-s1.0-phlox-light.png | 1440x234 | 720 | 1.0 | phlox-light | default |
| cell-agent-markdown-w720-s1.0-phlox-light.png | 1440x1959 | 720 | 1.0 | phlox-light | default |
| cell-command-group-collapsed-w720-s1.0-phlox-light.png | 1440x102 | 720 | 1.0 | phlox-light | collapsed |
| cell-command-group-expanded-w720-s1.0-phlox-light.png | 1440x102 | 720 | 1.0 | phlox-light | expanded（未達） |
| cell-reasoning-w720-s1.0-phlox-light.png | 1440x140 | 720 | 1.0 | phlox-light | default |
| cell-file-change-w720-s1.0-phlox-light.png | 1440x102 | 720 | 1.0 | phlox-light | collapsed |
| cell-task-list-w720-s1.0-phlox-light.png | 1440x298 | 720 | 1.0 | phlox-light | 常時展開 |
| cell-question-answered-w720-s1.0-phlox-light.png | 1440x304 | 720 | 1.0 | phlox-light | default |
| cell-question-expired-w720-s1.0-phlox-light.png | 1440x376 | 720 | 1.0 | phlox-light | default |
| cell-turn-cost-w720-s1.0-phlox-light.png | 1440x90 | 720 | 1.0 | phlox-light | default |
| cell-thinking-w720-s1.0-phlox-light.png | 1440x120 | 720 | 1.0 | phlox-light | システム Reduce Motion |

## できなかった項目と理由

- 折りたたみ/展開の両状態: `DisclosureCard` の Button は NSView AX に `折りたたみ中` を出さない。見出し Cell へ合成マウスイベントを送ると `ChatTranscriptView` 側でハングした（ADR 0030 系の再レイアウトを疑う）。製品コードは触らない制約のため、展開 PNG は折りたたみと同じ。コマンドグループ・Reasoning・差分・20行超出力の展開内容は未撮影。
- Reduce Motion の両状態: `accessibilityReduceMotion` は WritableKeyPath ではなく `.environment` で上書きできない。システム設定は変更しない。Thinking は実行時のシステム値で 1 枚。
- トランスクリプト上の処理中表示: 切断クライアントで `startNew` しないため `status` は starting、`showsProcessingIndicator` は false。Thinking は個別セルのみ。
- 空出力グループのカード: 連続空白コマンド 2 件は `shouldRender=false` で描かれない（製品挙動）。fixture には入れてある。
- 課金セッションでの代替はしていない。

## 追補（展開状態）

セル本体（`CommandGroupCell` / `ReasoningSummaryView` / `FileChangeCell` / `CommandGroupExecutionRow`）に展開を渡す init・環境値・`@AppStorage` 記憶キーは無い。合成マウスは使っていない。

使った経路:

- `DisclosureCard.init(isExpanded: Binding<Bool>)`（`ChatMessageCellsCommon.swift:55-67`）。ハーネスは `.constant(true)`。
- `CommandGroupExecutionDisplayData.outputDisplay(isExpanded:)`（`ChatMessageCells+CommandGroup.swift:73-77`）。20 行超は `true` で全文。

セル側に無く、製品コード変更なしでは使えない根拠:

- `CommandGroupCell`: `@State private var isExpanded = false`、init は `items` / `lastTranscriptID` / `isTurnRunning` のみ（`ChatMessageCells+CommandGroup.swift:163-175`）
- `ReasoningSummaryView`: `@State private var isExpanded = false`（`ChatMessageCells+Structured.swift:195-196`）
- `FileChangeCell`: `@State private var userExpandedOverride: Bool?` 初期 nil。`FileChangeDisplayPolicy.isExpanded(userOverride: nil, lineCount:)` は常に `false`（`ChatMessageCells+Structured.swift:291-316`、`ChatMessageRenderCache.swift:181-183`）。`defaultExpanded` は描画予算用でカードには使わない
- `CommandGroupExecutionRow`: `private struct`、`@State private var isOutputExpanded = false`（`ChatMessageCells+CommandGroup.swift:232-235`）
- 展開記憶の `@AppStorage` キーはソースに無い

描画: 幅 720pt・倍率 1.0・phlox-light / dracula。`ImageRenderer` でホスト確認（`AcceptanceCommandGroupRecapHeaderTests` と同じ）、PNG は既存ハーネスの `NSHostingView` + `cacheDisplay`（2x）。`CommandGroupExecutionRow` は private のため、同一の `ChatCodeCard` / `CommandGroupExecutionDisplayData` / `outputDisplay(isExpanded: true)` で合成。

PNG（`/tmp/phlox-t13-visual.SPfR9c/t40-gateB/`、pixelWidth x pixelHeight）:

| ファイル | 寸法 |
| --- | ---: |
| expanded-command-group-w720-s1.0-phlox-light.png | 1440x1198 |
| expanded-command-group-w720-s1.0-dracula.png | 1440x1198 |
| expanded-reasoning-w720-s1.0-phlox-light.png | 1440x240 |
| expanded-reasoning-w720-s1.0-dracula.png | 1440x240 |
| expanded-file-change-w720-s1.0-phlox-light.png | 1440x352 |
| expanded-file-change-w720-s1.0-dracula.png | 1440x352 |
| expanded-output-20plus-w720-s1.0-phlox-light.png | 1440x864 |
| expanded-output-20plus-w720-s1.0-dracula.png | 1440x864 |

折りたたみセルとの差: コマンドグループ 1440x102 → 1440x1198、Reasoning 1440x140 → 1440x240、差分 1440x102 → 1440x352。バイト不一致。経路メモ: `expanded-path.txt`。トランスクリプト全体の展開 PNG・Reduce Motion・処理中表示は未達のまま。

## 検証原文

```
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-gateB-compile swift test --filter TranscriptTypographyRenderHarness)
✔ Test run with 1 test in 1 suite passed after 0.001 seconds.

(cd macos/Packages/SessionFeature && TRANSCRIPT_TYPOGRAPHY_HARNESS_OUT=/tmp/phlox-t13-visual.SPfR9c/t40-gateB ~/.agents/scripts/compact-test t40-gateB swift test --filter TranscriptTypographyRenderHarness)
✔ Test run with 1 test in 1 suite passed after 29.569 seconds.

(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-gateB-full swift test)
✔ Test run with 902 tests in 113 suites passed after 1.215 seconds.
```

環境変数なしの filter 実行は 0.001 秒で成功（描画せず）。SessionFeature 全数は GREEN。コミットしていない。

追補:

```
(cd macos/Packages/SessionFeature && TRANSCRIPT_TYPOGRAPHY_HARNESS_OUT=/tmp/phlox-t13-visual.SPfR9c/t40-gateB ~/.agents/scripts/compact-test t40-gateB2 swift test --filter TranscriptTypographyRenderHarness)
✔ Test run with 1 test in 1 suite passed after 32.494 seconds.

(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-gateB2-noenv swift test --filter TranscriptTypographyRenderHarness)
✔ Test run with 1 test in 1 suite passed after 0.001 seconds.
```

環境変数なしの filter 実行は 0.001 秒で成功（描画せず）。コミットしていない。

## 切り分け（テーマ配色の古さ）

PM 目視の「s1.0 dracula だけカード／表ヘッダーが暗い緑・赤、s0.8／s2.0 は明テーマの緑・薄灰」は、契約 B 節 6（テーマ変更と倍率変更を連続して行い、キャッシュが古い字体・色を返さない）の疑いだった。結論: **同一プロセス内の連続変更で古いテーマ色が残ったものではない。原因の所在はハーネスのホスト（色スキーム未指定）であり、製品の色キャッシュではない。**

### 実測

`TRANSCRIPT_TYPOGRAPHY_HARNESS_THEME=dracula` と `TRANSCRIPT_TYPOGRAPHY_HARNESS_SCALE` で 1 組合せだけ描く経路をハーネスに足し、別プロセスで dracula×0.8 と dracula×2.0 を出した。描画直前の `ThemeStore.active.id`／suite／standard はいずれも `dracula`（`isolated-active-theme-s0.8-dracula.txt`、`isolated-active-theme-s2.0-dracula.txt`）。

| ファイル | 寸法 | 幅pt | 倍率 | テーマ |
| --- | --- | ---: | ---: | --- |
| isolated-transcript-w360-s0.8-dracula-collapsed.png | 720x4122 | 360 | 0.8 | dracula |
| isolated-transcript-w360-s0.8-dracula-expanded.png | 720x4122 | 360 | 0.8 | dracula |
| isolated-transcript-w720-s0.8-dracula-collapsed.png | 1440x3424 | 720 | 0.8 | dracula |
| isolated-transcript-w720-s0.8-dracula-expanded.png | 1440x3424 | 720 | 0.8 | dracula |
| isolated-transcript-w360-s2.0-dracula-collapsed.png | 720x14028 | 360 | 2.0 | dracula |
| isolated-transcript-w360-s2.0-dracula-expanded.png | 720x14028 | 360 | 2.0 | dracula |
| isolated-transcript-w720-s2.0-dracula-collapsed.png | 1440x7844 | 720 | 2.0 | dracula |
| isolated-transcript-w720-s2.0-dracula-expanded.png | 1440x7844 | 720 | 2.0 | dracula |

`isolated-transcript-w720-s0.8-dracula-collapsed.png` は連続描画の `transcript-w720-s0.8-dracula-collapsed.png` と SHA256 先頭 16 桁 `ded7d35df17f795c` で一致。s2.0 も `1dfd0152224790c0` で一致。中点画素はどちらも dracula 背景 `(49,49,49)`。質問カード面は薄灰・明るい緑／赤のままで、単独プロセスでも再現する。連続描画の s1.0（`transcript-w720-s1.0-dracula-collapsed.png`）も同じ薄灰カードであり、倍率キーでテーマ色が入れ替わった証拠にはならない。

### 根拠（型・行）

ハーネス側:

- ホスト `hostedTranscript`（`TranscriptTypographyRenderHarness.swift:264-282`）は `.background(DSColor.chatBackground)` と `.defaultAppStorage(suite)` だけで、製品 `PhloxApp.swift:81` にある `.preferredColorScheme(ThemeStore.active.preferredColorScheme)` も `NSWindow.appearance` も付けない。
- テーマ id は suite（`@AppStorage`）と `UserDefaults.standard`（`DSColor` → `ThemeStore.active`）の両方へ書いており、単独描画時は一致している。書込順のずれがこの PNG 差の原因ではない。

製品側（キャッシュ仮説の否定）:

- `DSColor` は `static var` の計算プロパティで、都度 `ThemeStore.active` を読む（`Tokens.swift:97-114`）。`static let Color` ではない。`fillSubtle`／`fillSelected` は `textPrimary.color.opacity(0.05)`／`opacity(0.10)`（同:108-109）。不透明な chatBackground／chatTextPrimary は dracula のまま、半透明 fill だけがライトなウィンドウ面に合成されて薄灰・明るい緑に見える。
- `UserQuestionCell` は `@AppStorage(ThemeStore.themeKey)` と `let _ = themeID` で購読し、面は body 内の `DSColor.fillSubtle`／`chatSuccess.opacity`／`statusError.opacity`（`UserQuestionCell.swift:31`、`65-66`、`97-104`、`125-133`）。色を `@State` に固定していない。
- 表ヘッダーは `RichMarkdownView` の MarkdownUI テーマで `DSColor.fillSubtle`／`fillSelected`（`RichMarkdownView.swift:199-209`）。`static var themes: [String: Theme]` は `themeID:scale` で色を初回キャプチャする（同:22-40）。キーにテーマ id を含むので、同一プロセスで phlox-light のあと dracula を描いても「dracula:0.8」へ明テーマ色が残る経路ではない。単独プロセスでも同じ薄灰になることが決定打。
- `DisclosureCardPalette` は `static func` で都度 `DSColor` を返す（`ChatMessageCellsCommon.swift:4-12`）。`ChatMessageRenderCache` はハイライト等を `ThemeStore.active.id` 付きキーで持つだけで、質問カード面は保管しない。

製品で実行中にテーマを切り替えたとき: トランスクリプト各 View は `@AppStorage(ThemeStore.themeKey)` で UserDefaults を購読する（`ChatTranscriptView.swift:39-40`、`70-71` ほか）。`ThemeStore` は Observable ではなく、`active` が `UserDefaults.standard` を都度読む（`AppTheme.swift:432-435`、キャッシュは selectedID 一致時のみ `454-468`）。設定画面は同じキーへ書く（`SettingsView.swift:26`、`207`）。製品では AppStorage と `DSColor` がどちらも standard なので、ハーネス固有の suite／standard 分裂は起きない。ウィンドウの `preferredColorScheme` は `PhloxApp` が `ThemeStore.active` を購読せずに付けているため、実行中切替でウィンドウ外観だけ遅れる余地はある（今回の PNG 症状の主因ではない）。

allowed_paths: 今回の所在はハーネス（PM 所有）と `Tokens.swift` の半透明 fill（task-40 の allowed_paths 外）。`UserQuestionCell.swift`／`RichMarkdownView.swift` は allowed_paths 内だが、古いテーマ色を static／`@State` に固定しているわけではない。

### 検証原文

```
(cd macos/Packages/SessionFeature && TRANSCRIPT_TYPOGRAPHY_HARNESS_OUT=/tmp/phlox-t13-visual.SPfR9c/t40-gateB TRANSCRIPT_TYPOGRAPHY_HARNESS_THEME=dracula TRANSCRIPT_TYPOGRAPHY_HARNESS_SCALE=0.8 ~/.agents/scripts/compact-test t40-gateB-iso08 swift test --filter TranscriptTypographyRenderHarness)
✔ Test run with 1 test in 1 suite passed after 3.879 seconds.

(cd macos/Packages/SessionFeature && TRANSCRIPT_TYPOGRAPHY_HARNESS_OUT=/tmp/phlox-t13-visual.SPfR9c/t40-gateB TRANSCRIPT_TYPOGRAPHY_HARNESS_THEME=dracula TRANSCRIPT_TYPOGRAPHY_HARNESS_SCALE=2.0 ~/.agents/scripts/compact-test t40-gateB-iso20 swift test --filter TranscriptTypographyRenderHarness)
✔ Test run with 1 test in 1 suite passed after 4.835 seconds.

(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-gateB-iso-noenv swift test --filter TranscriptTypographyRenderHarness)
✔ Test run with 1 test in 1 suite passed after 0.001 seconds.

(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-gateB-iso-full swift test)
✔ Test run with 902 tests in 113 suites passed after 1.257 seconds.
```

環境変数なしの filter 実行は 0.001 秒で成功（描画せず）。SessionFeature 全数は GREEN。コミットしていない。

## PM 判定（2026-09-13、Claude=PM が PNG を目視）

閲覧: `transcript-w720-s1.0-{phlox-light,dracula}-collapsed.png`、`transcript-w360-s1.0-phlox-light-collapsed.png`、`transcript-w720-s{2.0,0.8}-dracula-collapsed.png`、`cell-agent-markdown-w720-s1.0-phlox-light.png`、`expanded-command-group-w720-s1.0-phlox-light.png`、`expanded-output-20plus-w720-s1.0-phlox-light.png`。

- 読順: ユーザー入力（右寄せ吹き出し）→ H1 → 本文 15 → 長い H2 の折り返し → H3〜H6 の段階 → 箇条書き・番号（入れ子の字下げ、マーカー重なりなし）→ 表 → コード（水平方向へ到達、末尾で切れずカード内で続く）→ 処理見出し（semibold、右に chevron）→ 差分 `+2 -1` の意味色 → タスク各状態（未着手・実行中 semibold・完了の取り消し線＋補助色）→ 質問カード（回答済み／期限切れ）→ 料金 10pt 右寄せ → 次のユーザー入力。幅 360 でも同じ順で崩れなし。
- 間隔: 回答内 8 と処理カード群の詰まり、ユーザー入力前後の 16／24 の差が目視で区別できる。倍率 0.8／2.0 で文字だけ拡縮し、カード間隔は一定。
- 展開: コマンドグループ展開（見出し 15 semibold → Bash カード → 出力 mono）、20 行超の出力全文、Reasoning・差分の展開セルを確認。欠けなし。
- テーマ: phlox-light の全高 PNG は背景が透過（黒）で描かれるがハーネスのホスト背景の問題で、セル単位 PNG と実アプリ（ゲート A）は明背景。dracula の質問カード面が薄灰に見える件は切り分け節どおりハーネス（`preferredColorScheme` 未指定で半透明 fill が明面に載る）と判定。製品側のキャッシュは実コードで否定された。
- **ゲート B: pass**。未達のまま残す項目: Reduce Motion 両状態（システム設定を変えない方針）、処理中インジケーター（切断クライアントでは出ない）。これらは実装ではなくハーネスの限界として記録する。
- 判定外の観測: `PhloxApp` の `preferredColorScheme` が `ThemeStore.active` を購読せず、実行中のテーマ切替でウィンドウ外観だけ遅れる余地（allowed_paths 外・未再現）。フェーズ 5 で追跡項目として記録。

=== REPORT COMPLETE ===
