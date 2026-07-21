---
status: active
last-verified: 2026-07-21
---

# ADR 0112: ヘッダーの使用量表示を設定で消せるようにし、「未取得のCLIも表示」をヘッダーにも適用する

## 文脈

ヘッダー（ウィンドウ上部トップバー）の CLI 使用量チップには2つの問題があった。

1. **ユーザーが消せない。** 表示/非表示はアプリ側の都合（インスペクター表示中は出さない・幅が足りなければ縮退）でのみ決まり、「常に出さない」という利用者の意思を表す手段が無かった。
2. **設定「未取得のCLIも表示」（`phlox.usage.showUnavailable`）の適用範囲がラベルと食い違っていた。** この設定を読んでいたのは右インスペクター（`UsageSidebarView`）だけで、ヘッダー（`UsageTopBarView`）は `UsageDisplay.visibleKinds(usages:showUnavailable: false)` と直値を渡して設定を無視していた。ラベルは表示全般に効くように読めるため「この設定は形骸化しているのでは」という疑いを生んだ（実際には形骸化しておらず、効く範囲がインスペクターだけだった）。

## 決定

1. **新しい設定 `phlox.usage.showInHeader`（ラベル「ヘッダーに使用量を表示」・既定 `true`）を追加する。** キーと既定値の正本は `UsageSettings`（既定値は `defaultsDictionary` → `PhloxApp` の `UserDefaults.standard.register` 経路）。
2. **ヘッダーの表示可否を純関数 `UsageDisplay.showsTopBarUsage(showInHeader:inspectorVisible:)` に集約する。** 「設定オン かつ インスペクター非表示」のときだけ出す。インスペクター表示中は出さないという既存の排他（同じ情報が詳細で見えるため）は維持する。
3. **「未取得のCLIも表示」をヘッダーにも適用する。** `UsageTopBarView` が `@AppStorage(UsageSettings.showUnavailableKey)` を読み、ヘッダーとインスペクターが同じ `visibleKinds` を同じ設定値で通る構造にする。ラベルどおりの意味へ揃え、片方だけ設定を無視する不整合を構造的に再発させない。
4. **ヘッダーのチップ構築を `UsageDisplay.topBarChips(usages:showUnavailable:now:)` へ抽出する。** View 内の private ロジックはテストできず、(3) で振る舞い（`.unavailable` の扱い）が変わる以上、既存契約を退行なく保てないため。`now` は引数で受け、`TimelineView` は毎分 `context.date` で純関数を呼び直す。View 側で `staleNote` を再計算していた重複は廃止し、View を表示専用にする。

## 検討して棄却した案

- **現状維持＋ラベルで範囲を明示**（「サイドバーに未取得のCLIも表示」等に改名）: 変更は最小だが、ヘッダーとサイドバーで同じ概念に別の規則が残る。利用者の選択により棄却。
- **否定形の設定**（「ヘッダーに使用量を表示しない」・既定オフ）: 依頼の文言には忠実だが、同じセクションの既存3トグルがすべて肯定形＝オンで有効のため、向きが混在して読みづらい。
- **ヘッダー用に別の除外規則を持つ**: 表示面ごとにフィルタが増えるほど、今回と同じ「片方だけ設定を無視する」不整合を生む。

## 結果

- 既定オンのため、アップデートで既存ユーザーの見た目は変わらない。
- ADR 0039（Claude の使用量行は未取得でも消さず理由を出す）と ADR 0099（`.ok` の実データ表示中に鮮度注記テキストを重ねず淡色化のみ）は維持する。両方とも凍結受け入れテストで固定した。
- 「未取得のCLIも表示」をオンにすると、ヘッダーにも未取得の CLI が理由つきチップとして並ぶ。狭いウィンドウではチップ数が増えるぶん既存の縮退（ゲージ付き→直列テキスト→非表示）に早く入る。既定オフのため影響はオンにした利用者に限られる。
- 契約の凍結: `DashboardFeatureTests/Acceptance/HeaderUsageVisibilityAcceptanceTests.swift`。

## 検証

- `swift test --package-path macos/Packages/DashboardFeature` 1400 pass / `macos/Packages/AgentDomain` 175 pass、`xcodebuild -scheme Phlox -configuration Debug build` BUILD SUCCEEDED。
- デバッグビルドを実起動し、設定「ヘッダーに使用量を表示」のオン/オフでヘッダーのチップが消える・戻ることを目視確認（アプリ再起動なしで即反映）。
- 未確認: 「未取得のCLIも表示」をオンにしたときのヘッダー表示の目視。確認時点の実機では Claude・Codex・Cursor の3つとも使用量を取得できており、未取得状態を作れなかった（振る舞いは受け入れテストで固定済み）。
