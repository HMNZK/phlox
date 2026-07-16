---
status: active
last-verified: 2026-07-10
---

# 0068: 終了シグナルハンドラは @Sendable 受け取りの公開 API で isolation 継承を型レベルで遮断する

> 番号注記: 0067 は未マージの feature/composer-agent-ux ブランチが使用中のため、衝突回避で 0068 を採番した。

## 文脈

SIGTERM/SIGINT 受信時に Phlox（Xcode 26.2 ビルド）が SIGTRAP で即クラッシュし、グレースフル終了（子セッション一括終了→exit 0）が一切走らず子プロセスが孤児化していた（実測: `kill -TERM` → exit 133。クラッシュレポート 2026-07-10 05:14/05:17 の2件も同一スタック）。

真因は `App/PhloxApp.swift` の `installSignalHandlers()`。`source.setEventHandler { [weak self] in self?.handleTerminationSignal() }` のクロージャは **@MainActor 文脈（AppDelegate のメソッド内）で生成された非 Sendable クロージャのため MainActor isolation を継承**し、シグナル監視キュー（`com.phlox.signal-cleanup`）で実行された瞬間にランタイムの executor チェック（`swift_task_isCurrentExecutorWithFlags` → `dispatch_assert_queue`）に落ちる。呼び先 `handleTerminationSignal()` 自体は `nonisolated` で「MainActor ブロック中でも完走する」設計だったが、**入口クロージャの isolation が設計意図を裏切っていた**。逆アセンブルでクロージャ先頭に MainActor executor チェックが埋め込まれていることを確認済み。

## 決定

1. シグナル設置ロジックを `Packages/AppBootstrap` の公開 API へ抽出する:
   `TerminationSignalHandlers.install(signals:queue:handler:)`（handler は `@escaping @Sendable () -> Void`、返り値 `[DispatchSourceSignal]` は呼び出し側が保持）。**@Sendable を署名に置くことで、呼び出し元がどの actor 文脈でも isolation 継承が型レベルで起こらない**（コメントや規約でなくコンパイラが担保）。
2. App 側は Sendable な依存（`CleanupGuard`・`SignalSafeBox<PTYManager?>`）だけを明示キャプチャした `@Sendable` クロージャから、`nonisolated static` 化した終了処理を呼ぶ（`self`＝MainActor 隔離の AppDelegate をキャプチャしない）。
3. 終了処理のセマンティクスは不変: `SIG_IGN`→設置→`resume` の順序、CleanupGuard による高々1回、`terminateAllAndWait(timeout:)` 完了待ち→`exit(0)`、MainActor 非経由（メインスレッドブロック中でも完走）。

## 棄却した代替案

- **インプレース修正（App/ 内で @Sendable 注釈のみ）**: クラッシュは消えるが、App ターゲットにはテストバンドルが無く回帰テストを置けない。AppBootstrap 抽出なら受け入れテスト（実シグナル送達・非メインスレッド発火・MainActor 文脈からの設置で SIGTRAP しない）を凍結できる。
- **handler 内で MainActor へホップして安全化**: 「MainActor ブロック中の SIGTERM でデッドロック」という元の設計要件（SignalSafeBox 導入の理由）に反するため不可。

## 結果

- `kill -TERM` / `kill -INT` → exit 0・クラッシュレポートなし（修正前は exit 133）を実バイナリで実測。
- 受け入れテスト: `AcceptanceTerminationSignalTests`（3件。うち1件は **@MainActor テストから設置しても SIGTRAP しない**という旧バグの直接回帰テスト）。AppBootstrap 79 tests green。
- 教訓（普遍）: **@MainActor 文脈で生成した非 Sendable クロージャを GCD（DispatchSource/DispatchQueue）へ渡すと isolation を継承し、実行時 executor チェックで trap しうる**。GCD 境界へ渡すクロージャは @Sendable 型の引数で受けるか、明示的に nonisolated な生成点を持たせる。swift test では検出できず（App ターゲット外）、実バイナリへの実シグナル送達でのみ顕在化していた。

## 残余・未解決

- 2026-07-10 05:14/05:17 のクラッシュで SIGTERM/SIGINT を送った主体は未特定（unified log 消失）。当時 Debug flavor の二重起動（未サポート状態）だったことのみ確認。ブランチ picker UI 経路は単一インスタンスの実機再現でクラッシュせず、シグナル送達との相関は間接的とみられる。
- リリース版（/Applications・旧 Xcode ビルド）が同一クラッシュを持つかは未検証。本修正のリリース反映で解消する。

## 関連

- コード: `Packages/AppBootstrap/Sources/AppBootstrap/TerminationSignalHandlers.swift`、`App/PhloxApp.swift`（`installSignalHandlers` / `handleTerminationSignal`）、`SignalSafeBox.swift`・`CleanupGuard.swift`（既存）
- テスト: `Packages/AppBootstrap/Tests/AppBootstrapTests/AcceptanceTerminationSignalTests.swift`（凍結）・`TerminationSignalHandlersTests.swift`
- 実装/検証: b980fa6（凍結テスト）→ 5e4c6c3（修正）。run 経緯は delivery/0036。
