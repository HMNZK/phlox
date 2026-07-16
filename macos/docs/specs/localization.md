---
status: active
last-verified: 2026-07-04
---

# アプリ内多言語化（日本語 / 英語のライブ切替）

Phlox の UI を日本語 / 英語でアプリ内切替する仕組みと、**新規文言の追加手順**・**制約**をまとめる。実装は `feature/new-feature`（統合 `495bac5`）。

## 方針（なぜこの形か）

| 論点 | 採用 | 理由 |
|---|---|---|
| カタログ | **App ターゲット単一** `App/Localizable.xcstrings`（String Catalog, `sourceLanguage: ja`） | SwiftUI の `Text("…")` / `String(localized:)` は**既定で main bundle を参照**する。よってパッケージ（DashboardFeature/DesignSystem）の文言も**単一の app カタログ**で解決でき、パッケージ別 `Bundle.module` 設定が不要。 |
| キー戦略 | **日本語リテラルをそのままキーにする** | `Text("エージェントを選んでセッションを開始")` のような日本語リテラルは既に `LocalizedStringKey`。呼び出し側を変えずカタログに英訳を足すだけでローカライズできる（churn 最小）。 |
| 切替方式 | `@AppStorage("phlox.appLanguage")` + ルート Scene への `.environment(\.locale, …)` 注入 | OS 言語に依存せず**アプリ内で明示切替**。SwiftUI の `Text` は環境 locale に追従し**再起動なしでライブ切替**される。 |

- `project.yml`: `options.developmentLanguage: ja`（ソース言語＝日本語）。
- 言語選択の単一真実源: `App/LanguageSettings.swift`（`AppLanguage` enum: `.system`=`Locale.autoupdatingCurrent` / `.ja` / `.en`、既定 `"system"`）。
- 注入点: `App/PhloxApp.swift` の `WindowGroup` 内コンテンツと `Settings { … }` の**両方**に `.environment(\.locale, appLanguage.locale)`。
- 設定 UI: `App/SettingsView.swift` の「言語」セクション（システム / 日本語 / English）。

### ステータス表示は二言語関数を locale で選択
`StatusLabel` / `StatusDot`（DesignSystem）は元から英語表示だった。`StatusBadge.localizedLabel(for:locale:)` を追加し、`@Environment(\.locale)` を見て `label`(日) / `englishLabel`(英) を選ぶ（カタログ非経由・既存関数を活用）。これによりステータスもライブ切替される。

## 新規 UI 文言を追加するとき（手順）

1. **SwiftUI のローカライズ引数に渡る文言**（`Text` / `Button` / `Label` / `.help` / alert・confirmationDialog のタイトル等）:
   - 呼び出し側は**日本語リテラルのまま**書く（例: `Text("新しい設定")`）。リテラル＝キー。
   - `App/Localizable.xcstrings` に同じ日本語をキーとして en 訳を追加（書式は既存エントリに合わせる。フォーマット指定子 `%@`/`%lld` は英訳でも保持）:
     ```json
     "新しい設定": {
       "extractionState": "manual",
       "localizations": { "en": { "stringUnit": { "state": "translated", "value": "New setting" } } }
     }
     ```
2. **String として組み立てる文言**（ViewModel のエラー、通知本文など SwiftUI `Text` に直接渡らないもの）:
   - `String(localized: "日本語キー")` でラップ（`bundle:` 引数は付けない＝既定 main bundle）。同様にカタログへ en 訳を追加。
3. **ビルドで反映確認**:
   ```bash
   xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath /tmp/PhloxBuild build
   plutil -p /tmp/PhloxBuild/Build/Products/Debug/Phlox.app/Contents/Resources/en.lproj/Localizable.strings | grep "新しい設定"
   ```
   `en.lproj` / `ja.lproj` が生成され、キー→英訳が出れば OK。

> パッケージ（DashboardFeature/DesignSystem）の文言も**この app カタログに追記**する（パッケージ側にリソースを足さない）。`Text("…")` は main bundle を見るため解決される。

## 制約（ライブ切替されない surface）

`.environment(\.locale)` は SwiftUI の `Text` 系にのみ効く。次は**アプリ内ピッカーでは即時切替されず OS ロケールに従う**（仕様上の制約。要件次第で別途対応）:

- **メニューバー**（`Scene` の `.commands`）: WindowGroup 内の environment を受けないため切替されない。
- **NSOpenPanel / NSAlert 等の AppKit パネル**。
- **UserNotifications の通知文**。
- **`String(localized:)` 系**: 呼び出し時点の locale で1回解決されるため、生成済み文字列（通知・エラー・Usage の reason/label）はピッカー変更に即時追従しない。

## 検証の勘所

- ビルド後に `en.lproj` / `ja.lproj` が生成され、`en.lproj/Localizable.strings` にキー→英訳が入っているか（`plutil -p`）。
- 機械照合: ソースの日本語リテラル（`Text("…")` 等）が全てカタログにキーとして存在するか（補間は `%@` 正規化されるので注意）。`#Preview` 内のサンプル文言は対象外。
- オーケストレーション手順の日本語（現在は `/phlox-cli` スキル。旧 `OrchestrationGuide` は ADR 0035 で撤去）はエージェントへ渡すプロンプト本文（UI ではない）なのでローカライズ対象外。

## 関連

- コード: `App/LanguageSettings.swift`, `App/Localizable.xcstrings`, `App/PhloxApp.swift`, `App/SettingsView.swift`, `Packages/DesignSystem/Sources/DesignSystem/StatusBadge.swift`（`localizedLabel`）/`StatusLabel.swift`/`StatusDot.swift`, `project.yml`（`developmentLanguage: ja`）。
- 実装/マージ: `9a4e214`（基盤＋App ターゲット）, `ba3089a`（DashboardFeature）, `13669da`（ステータス表示）, 統合 `495bac5`。
- ADR 0005（プライバシーセクションの文言も同カタログで日英対応）。
