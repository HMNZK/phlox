---
id: task-35
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceThemePreviewModelTests.swift
baseline_commit: 094f86a
contract_tests: []
allowed_paths:
  - macos/Packages/DesignSystem/Sources/DesignSystem/ThemePreviewModel.swift
  - macos/App/SettingsView.swift
---

## 目的

UI-06。テーマ一覧の色帯だけでは、適用後のアプリ外観を判断できない。
背景・本文・現在の会話行・入力欄を含む小さな見本と、用途を明記したターミナル配色の色帯を並べる。
新しいテーマや配色規則は追加しない。

仕様の観察・改善案・完了条件は `macos/docs/specs/ui-ux-improvement-backlog.md:169`。
現在の描画は `macos/App/SettingsView.swift:383,490`。
アプリ用RGBとターミナル用RGBは `macos/Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift:64,83` で別々に保持され、
アプリ用のグレー化は同ファイル `:200` で行われる。

## 入出力契約

- 新設 `ThemePreviewModel`（`ThemePreviewModel.swift`、public struct、Equatable、Sendable）:
  - SwiftUI・AppKitをimportしない。公開値は既存の `RGB`、String、Double、配列、以下の純粋値型だけとし、Color・View・ColorSchemeを保持しない。
  - `public struct Layer: Equatable, Sendable { public let rgb: RGB; public let opacity: Double }`
  - `public static func make(theme: AppTheme) -> ThemePreviewModel`
  - `themeID: String` = `theme.id`。
  - `themeName: String` = `theme.name`。
  - `appLabel: String` = `"アプリ外観"`。
  - `terminalLabel: String` = `"ターミナル配色"`。
  - `bodyText: String` = `"本文の見本"`。
  - `selectedRowText: String` = `"現在の会話"`。
  - `inputText: String` = `"メッセージを入力"`。
  - `background: RGB` = `theme.background`。
  - `textPrimary: RGB` = `theme.textPrimary`。
  - `currentMarker: RGB` = `theme.accent`。
  - `selectedRow: Layer` = `Layer(rgb: theme.textPrimary, opacity: AppTheme.sidebarSelectedOpacity)`。
  - `inputFill: Layer` = `Layer(rgb: RGB(255, 255, 255), opacity: 0.04)`。
  - `inputBorder: Layer`:
    - `theme.background.relativeLuminance >= 0.5` なら `Layer(rgb: theme.textPrimary, opacity: 0.86)`。
    - それ以外は `Layer(rgb: RGB(255, 255, 255), opacity: 0.06)`。
    - 既存の `AppTheme.preferredColorScheme` と同じ輝度判定を、既存のRGB計算で行う。SwiftUIの型は使わない。
  - `terminalSwatches: [RGB]` = `[theme.terminalBackground] + Array(theme.ansi[1...6]) + [theme.terminalForeground]`。
  - 事前条件: 入力は製品が登録しているAppThemeで、ANSI配列は16色。任意長のパレット編集機能は扱わない。
  - ThemeStore.active、UserDefaults、ファイル、プロセス、グローバルな選択状態を参照・変更しない。渡された候補テーマだけから決定する。

- 配色対応の根拠:
  - 選択行は `macos/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift:109,164` の「主文字色を10%重ねる」描画に対応する。不透明な事前合成色へ置き換えない。
  - 入力欄は `macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift:117` と `GridChatColumn.swift:281` の「chatBackgroundに白4%を重ねる」描画に対応する。
  - 入力欄の枠は `macos/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift:138` の明色86%・暗色白6%に対応する。
  - 輝度判定の正本は `macos/Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift:87`。
  - これらは既存描画の写像であり、新しい配色仕様ではない。配線検査で製品側のレシピとの一致を固定する。

- 配線（`SettingsView`）:
  - `ThemeRowView` の候補ごとに `ThemePreviewModel.make(theme: theme)` を呼ぶ。
  - 既存の `Button(action: onSelect)` のラベル内に、テーマ名、アプリ外観の見本、ターミナル配色の色帯、既存の選択チェックを配置する。
  - アプリ見本は `ThemeAppPreview(model:)`、色帯は `ThemeSwatchStrip(model:)` とし、両方を同じmodelで描く。新しいViewはSettingsView.swift内に置く。
  - アプリ見本は不透明な `model.background.color` を下地とし、`model.textPrimary.color` の本文、`model.selectedRow` を重ねた現在の会話行、`model.inputFill` と `model.inputBorder` を重ねた入力欄を描く。
  - 現在の会話行は本文より太くし、leading側に `model.currentMarker.color` の小さなマーカーを出す。既存UI-08の「現在の会話」という意味を保つ。
  - 各Layerは `.rgb.color.opacity(.opacity)` で適用する。入力欄にも不透明なmodel.backgroundの下地を敷き、設定行のhover・選択色が透け込まないようにする。
  - `Text(model.appLabel)` と `Text(model.terminalLabel)` を実際に表示する。用途をhelpだけに隠さない。
  - 色帯は `model.terminalSwatches` の順に描く。アプリ見本にterminalBackgroundやANSI色を背景色として流用しない。
  - 見本の入力欄はTextと図形で描き、TextFieldやTextEditorにはしない。テーマ選択Button内に別の操作を入れない。
  - テーマ名・選択状態がAXから分かること。見本を別のフォーカス対象にせず、色帯の各矩形を独立した操作として読み上げさせない。
  - 候補見本内の色はmodel由来に限定する。見本の外側の説明・テーマ名・選択チェックは既存DSColorの使用を維持してよい。

- 参照可能性:
  - `macos/App/SettingsView.swift:5` は既にDesignSystemをimportしている。
  - `macos/Packages/DesignSystem/Package.swift:14,19` はSourcesとDesignSystemTestsを既存ターゲットとして持つ。
  - 新しいモデルとその公開プロパティをpublicにすれば、Appから参照できる。Package.swift・project.ymlの変更は不要。

- 不変条件:
  - ThemeStore.allの10テーマ、順序、ID、テーマRGB、テーマ保存キー、選択時の `themeID = theme.id` を変更しない（`AppTheme.swift:424`、`SettingsView.swift:77`）。
  - テーマ適用やターミナルへの反映処理を変更しない。ターミナル側の写像は `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift:656`。
  - 設定画面の他の項目・操作・保存処理を欠落させない。
  - 本草案は未凍結。テストとRuby検査はPMが作成し、未実装を原因とするredを確認してからbaseline_commitを設定する。実装役のallowed_pathsにテスト・検証スクリプトを含めない。
  - acceptance_testsのアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、PMに報告し承認を得たうえでハーネス部分に限り修理してよい。

## 成功基準

1. 凍結テスト `AcceptanceThemePreviewModelTests` green。
   Phloxでbackground=(17,17,17)、textPrimary=(230,230,230)、selectedRow=((230,230,230),0.10)、inputFill=((255,255,255),0.04)、inputBorder=((255,255,255),0.06)を字面で固定する。
   Phloxの色帯を [(14,14,14),(239,68,68),(52,211,153),(251,191,36),(96,165,250),(217,119,87),(56,189,248),(214,214,214)] に固定する（`AppTheme.swift:245,273`）。
   GitHub Lightではbackground=(255,255,255)、inputBorderのopacity=0.86、RGBが同テーマのtextPrimaryであることを確認する。
   文言5種、themeID/name、マーカー色、色帯の8色と順序を検査する。
   登録10テーマについて候補由来の背景・文字・選択行・枠・色帯への写像を検査し、各テーマで `bodyText` / `selectedRowText` / `inputText` / `appLabel` / `terminalLabel` の文言を固定する。Phlox→GitHub Light→Phloxの呼び出しで前の候補が混入しないことを確認する。
   `ThemePreviewModel` と `Layer` は `func requireEquatable<T: Equatable & Sendable>(_: T.Type)` で Equatable & Sendable を確認する。
   数値は実コード上のRGB・不透明度の契約であり、スクリーンショットの測色値ではない。
   `~/.agents/scripts/compact-test task35-design-system bash macos/scripts/run-swift-tests.sh DesignSystem` green。
   Appを含む隔離Debugビルド成功。統合時は既存 `.claude/verify.sh` を正本として実行し、パッケージテストの成功をAppのビルド成功と読み替えない。

2. 配線検査 `.claude/scripts/task35-wiring.rb` OK。
   PMが凍結し、`~/.agents/scripts/compact-test task35-wiring env TASK35_BASELINE=<凍結SHA> ruby .claude/scripts/task35-wiring.rb` で実行する。
   文字列リテラルを先にプレースホルダ化したうえで `//` と `/* */` を除去し、括弧・波括弧対応で対象View本文と引数を取り出して以下を検査する。
   ThemeRowViewが候補のthemeでmakeを呼ぶ／`ThemePreviewModel.make` の戻り値が変数に代入され、その変数が ThemeAppPreview と ThemeSwatchStrip の両方に渡る／アプリ・ターミナル双方の用途名をTextとして表示する／各見本がmodelの該当フィールドを実描画へ使う／selectedRowとinputFillは、それぞれを含む ZStack の先頭で不透明な `model.background` を下地にする／各Layerのopacityを適用する／色帯は `model.terminalSwatches` の直後に `.reversed()`・`.shuffled()`・添字が無い／見本内にDSColor・ThemeStore.active・UserDefaults・入力コントロールがない。
   既存のテーマ列挙、選択action、選択チェックが残ることを検査する。
   モデルのSwiftUI/AppKit importおよびColor/View/ColorScheme保持がないことを検査する。
   読み取り対象のTokens・ChatComposer・GridChatColumn・AppThemeについて、前述の選択面・入力面・枠・輝度判定が契約どおりであることを検査する。製品側だけ変更された場合も検査を落とす。
   SettingsViewの変更をテーマ行・テーマ見本に限定し、他の設定Sectionとactionの欠落を固定SHAとの差分で検出する。比較時は ThemeRowView / ThemeAppPreview / ThemeSwatchStrip を両側から空文字で除去した残余を使う（新規 struct がプレースホルダ残留で偽陽性にならないこと）。HEADとの自己比較は使わない。
   `--selftest` で、残余比較の正例・負例、文字列内 `//` を壊さないこと、`/* */` 除去、make 代入、入力欄 ZStack 先頭、色帯の順序改変拒否を自己検査する。

3. 隔離 Debug の App ビルド（`xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build`）成功を PM ゲートの必須項目とする。
   PM目視ゲート:
   この変更から作った隔離Debugを専用DerivedData・専用データディレクトリで起動する。
   `PHLOX_DATA_DIR`、`PHLOX_AGENTS_JSON`、専用defaults suiteを利用し、実際にテーマ選択を書き込むdefaultsドメインも隔離されていることを事前確認する。suite指定だけでSettingsViewのAppStorageまで隔離されたと仮定しない（`SettingsView.swift:26`）。
   起動結果から自PIDを取得し、実行ファイルパスとウィンドウ所有PIDを照合する。自PIDに対するAX取得・AXPress、必要時のみ遮蔽確認付き座標クリックを使用する。キー送信は禁止。
   DraculaとGitHub Lightについて、設定一覧の候補見本と、適用後の背景・文字・現在の会話行・入力欄を撮影して比較する。
   選択前から各候補が固有の配色であること、テーマ選択後も他候補の見本が同じ色に染まらないこと、用途名・テーマ名・チェックが通常の設定ウィンドウ幅で欠けないことを確認する。
   課金セッションの起動・メッセージ送信は要求しない。サイドバーとターミナルは隔離した `/bin/cat` のcustom agentを利用できる。製品のチャット入力欄を課金なしで表示する経路は本草案では未確認のため、PMが凍結前に既存の未接続セッション等による表示経路を実証する。実証できなければ入力欄との実画面比較は未達として残し、配色テストだけで代替合格にしない。
   スクリーンショットには対象テーマ・PID・ウィンドウ寸法を記録する。測色する場合は同じ表示環境で内部の平坦面を比較し、文字縁・枠のアンチエイリアスを色差と混同しない。
   終了時は自分が起動したPIDと子プロセスだけを確認して終了する。撮影不能・AX取得不能は未検証として記録する。

- PM 追記（2026-09-12）: 入力欄の実画面比較が済むか、ユーザーが比較免除を判断するまで、UI-06 は完了マークしない（UI-07 と同じ扱い）。他 3 要素（背景・本文・現在の会話行）と色帯の比較は先に行う。入力欄比較が未達のまま配色テストや他 3 要素の目視で代替合格にしない。

## レビュー観点（Rubric）

- アプリ外観とターミナル配色を、用途名と内容の両方で区別できる。
- 現在選択中のテーマではなく、各行の候補テーマから見本を描いている。
- 入力欄の白4%と選択行の主文字10%を、不透明な候補背景上に正しく重ねている。
- 配色の導出を変更せず、既存描画との対応を凍結テスト・配線検査・代表2テーマの実画面で別々に確認している。
- 見本のためにSettingsView全体を大きく作り替えず、テーマ名・選択チェック・他の設定への到達性を維持している。
- 小さな見本に実入力や追加のフォーカス対象を持ち込んでいない。
- 未測定の見本寸法や実描画色を検証済みと書いていない。入力欄を含むPM目視ゲート未達のままUI-06完了にしない。
