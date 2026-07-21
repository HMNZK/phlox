---
status: completed
last-verified: 2026-07-21
---

# 0013: ヘッダー使用量の表示設定 worklog

agentic-loop（multi・N=1・backend=claude）による run 記録。実装は `implementer` サブエージェントへ委譲し、
PM（Claude）が問題定義・受け入れテスト凍結・独立レビュー・統合検証・蒸留を担当。作業ブランチ
`feature/input-ux-and-cursor-usage`（dev と同一地点から開始・in-place）。

## 要望 / 現状

- 要望1: ヘッダー（ウィンドウ上部トップバー）に使用量を表示しない設定がほしい。
- 要望2（調査で判明）: 設定「未取得のCLIも表示」が形骸化していないかの確認 → 形骸化していないが、効く範囲が
  右インスペクター（`UsageSidebarView`）だけで、ヘッダー（`UsageTopBarView`）は `showUnavailable: false` を
  直値で渡して無視していた。ラベルとの乖離を解消するため、ヘッダーにも適用することをユーザーが選択。

決定の理由と棄却案は ADR 0112、現行構造は architecture/claude-usage-supply.md に記載。

## 何をしたか

| task | 内容 |
|---|---|
| task-1 | `UsageSettings.showInHeaderKey`（既定 true）追加／`UsageDisplay.showsTopBarUsage` と `UsageDisplay.topBarChips` を新設し `UsageTopBarView` のチップ構築を移設／`UsageTopBarView` が `showUnavailable` 設定を読むよう修正（直値除去）／`DashboardTopBarControls` の表示条件を差し替え／`SettingsView` にトグル追加 |
| PM（共有面） | `App/Localizable.xcstrings` に「ヘッダーに使用量を表示」の英訳を追加。あわせて未登録だった「未取得のCLIも表示」の英訳も登録（横断ファイルのため task の allowed_paths から除外して PM が担当） |

## レビュー（フェーズ3・ステージ1 = persona-reviewer）

- 初回 needs_changes（MEDIUM 1件）: `topBarChips` の `now`/`staleNote` が本番描画に効いていない。`TimelineView` 内で
  `chips.map { ... }` により Claude の `staleNote` を無条件に再計算・上書きしていたため、純関数側を検証する
  白箱テストが実効経路を守らない「偽の安全信号」になっていた。
- 差し戻し1回で修正（`map` ブロックを削除し `context.date` で純関数を呼び直す。行数は減少）→ 再レビュー pass。

## 検証

- `bash .claude/verify.sh`（凍結受け入れ＋既存の使用量スイート）62 tests / 6 suites pass。
- 統合: `swift test --package-path macos/Packages/DashboardFeature` **1400 pass**、`macos/Packages/AgentDomain` **175 pass**、
  `xcodebuild -project macos/Phlox.xcodeproj -scheme Phlox -configuration Debug build` **BUILD SUCCEEDED**。
- 目視（デバッグビルドを別インスタンスで起動。リリース版は終了させずに実施）: 設定画面「使用量」に
  「ヘッダーに使用量を表示」が並び、トグルのオフでヘッダーの使用量チップが消え、オンで戻ることを再起動なしで確認。
- 未確認: 「未取得のCLIも表示」をオンにしたときのヘッダー表示の目視。確認時点の実機では Claude・Codex・Cursor の
  3つとも使用量を取得できており未取得状態を作れなかった（振る舞いは凍結受け入れテストで固定済み）。

## 運用メモ

- デバッグビルドを起動中のリリース版と併存させる場合、`open -n --env "PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1"
  --env "PHLOX_DATA_DIR=<一時dir>" <Debug>/Phlox.app` で起動する。この env を付けないと adhoc 署名の
  Keychain ACL プロンプト（ログインキーチェーンのパスワード入力が必要）で「起動中...」から進まない。
  同名プロセスが2つ並ぶため System Events の AX 解決は当てにならず、ウィンドウ ID 指定の
  `screencapture -l<WID>` と `CGEvent`（`postToPid` でのショートカット投入）で操作・撮影するのが確実。

## 生成した永続ドキュメント

- ADR: `adr/0112-header-usage-visibility-setting.md`
- architecture: `architecture/claude-usage-supply.md`（表示可否と対象 CLI の決定を追記）
