---
status: active
last-verified: 2026-07-15
---

# ADR 0086: single モードのサイドバー・プロジェクト名選択で「新規セッション開始画面」を表示する（モード別導線）

> **このファイルの役割**: なぜサイドバーのプロジェクト**名**クリックを「常にグリッド切替」から「表示モード別の導線」へ変えたかの決定。
> **書かないもの**: 空状態カードの現行構成（→ `architecture/dashboard-empty-state-agent-cards.md`）、既定バックエンドの決定（→ ADR 0071）、カード×モード選択（→ ADR 0082）。

## 文脈

ADR 0071（R4）で、サイドバーのプロジェクト**名**クリックは「既存のグリッド絞り込みに追乗」する形にした結果、`onToggleFilter` が `selectProject` → `toggleGridFilter` → `viewMode = .grid` を**無条件**に実行し、表示モードに関わらず常にグリッドビューへ切り替わっていた。このため、シングルビュー（`.single`）でプロジェクトを選んで「新規セッション開始画面」（空状態のエージェント選択カード `AgentStartCards`、ADR 0082）へ入る導線が塞がれていた（single で当該画面が出る条件 `viewMode==.single && selectedSession==nil && selectedProjectID!=nil` はコードに既存だが、名前クリックが強制的に `.grid` にするため到達できない）。

ADR 0071 line 30 は、この挙動を「既知の UI ニュアンス」かつ「レビュー LOW（意図確認待ち）」として残していた。ユーザー要望（2026-07-15）: 「シングルビューモードのときにプロジェクトを選択したら、新規セッション開始画面を表示してほしい」。

## 決定

1. **モード別導線に集約**: `AppRouter` に `selectProjectFromSidebar(_ projectID:)` を追加し、名前クリックのロジックをここへ集約（ユニットテスト可能化）。
   - `.single`: `selectProject(projectID)` して `selectedSession = nil`（`viewMode` は `.single` のまま）。→ 新規セッション開始画面が表示される。
   - `.grid` / `.team`: 従来どおり `toggleGridFilter(projectID:)` ＋ `viewMode = .grid`（挙動不変）。
2. **対象は名前クリックのみ**: `DashboardSidebarView.projectHeader` の `onToggleFilter` を上記メソッド1呼び出しへ置換。プロジェクト**アイコン**ボタン（`onSelectProject` = `selectProject` のみ）は現状維持。
3. **開いているセッションは閉じる**: single では既存セッションを開いていても閉じて（`selectedSession=nil`）新規画面を確実に出す。
4. **ツールチップの中立化**: 名前テキストの `.help` を「グリッドをこのプロジェクトで絞り込み」から「このプロジェクトを選択」へ（single では絞り込みではなくなるため）。

## 棄却案

- **セッション未選択時のみ新規画面（開いているセッションは維持）**: 名前クリックで確実に新規画面へ入れず、「選択したら新規画面」という要望を満たさない。ゲート①で「閉じて表示」を選択。
- **名前・アイコン両方を新挙動に統一**: UI 一貫性は上がるが変更範囲が広がる。要望は名前クリックが対象のため名前のみに限定（ゲート①）。
- **team モードも single と同じ新挙動へ**: 要望外・スコープ外。team は従来どおり（`.grid` へ）維持。

## 結果

- 凍結受け入れテスト `AcceptanceSingleModeProjectSelectTests`（2件: single での session クリア＋`StartAreaPolicy==.agentStartCards`／grid でのフィルタトグル維持）を追加。`swift test`（DashboardFeature）全 green（1327 件）＋ macOS アプリ Debug ビルド成功で検証。
- ADR 0071 line 30 の「既知の UI ニュアンス（名前クリック＝グリッド切替・レビュー LOW 意図確認待ち）」を、single モードについて解消。0071 の既定バックエンド決定自体は不変（本 ADR は 0071 の UI 導線を single モードで具体化・更新する位置づけ）。
