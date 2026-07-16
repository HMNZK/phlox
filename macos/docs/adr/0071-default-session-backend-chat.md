---
status: active
last-verified: 2026-07-10
---

# ADR 0071: 新規セッションの既定をチャット（appServer）にし、設定で選択可能にする

> **このファイルの役割**: なぜ GUI からの新規セッションの既定バックエンドを pty（ターミナル）から appServer（チャット）へ変えたか、適用範囲をどこで区切ったかの決定。
> **書かないもの**: spawn の内部仕様（→ `architecture/claude-chat-session-lifecycle.md`）、セレクトカードの構成（→ `architecture/dashboard-empty-state-agent-cards.md`）。

## 文脈

組込み3エージェント（Claude Code / Codex / Cursor）は全て structured chat 対応になり、日常利用の主経路はチャット UI に移った。しかし新規セッションの既定は `.pty` 固定で、チャットで始めたいユーザーが毎回切り替える必要があった（ユーザー要望 2026-07-10）。

## 決定

1. **既定チャット化**: `DefaultSessionBackendPreference`（AgentDomain）を新設。未設定・不明値は `.chat`。`resolveBackend(supportsStructuredChat:)` が `.chat`×非対応 → `.pty` へ**フォールバック**（エラーにしない）、`.terminal` → 常に `.pty`。
2. **設定画面**: SettingsView に「デフォルトの開き方（チャット/ターミナル）」Picker を追加（`@AppStorage`、キーは `DefaultSessionBackendPreference.storageKey` を直参照し文字列二重定義を排除）。
3. **適用範囲は GUI の対話的な新規セッション作成のみ**（`spawnNewSessionUsingDefaultProject` 経由: セレクトカード・メニュー・ショートカット）。`spawnNewSession(ref:...)` の既定引数 `.pty`、API/orchestration 経路（backend 明示指定）、親チャット→子チャットの昇格ロジック（昇格のみ・降格なし）は**不変**。
4. **プロジェクト選択との連動（R4）**: セレクトカードは「プロジェクト選択済み・セッション未選択」のときだけ表示（`StartAreaPolicy` 純関数）。プロジェクト選択は `AppRouter.selectedProjectID`（非永続）で、サイドバーのプロジェクトアイコンクリック（`onSelectProject`）または名前クリック（既存のグリッド絞り込みに追乗）で設定。カード spawn は選択中プロジェクトへ向ける。

## 棄却案

- **全 spawn 経路の既定変更**: API/orchestration の挙動（明示指定前提）を壊す。GUI 対話経路に限定。
- **非対応エージェントでのエラー**: カスタム ref の起動が既定変更で失敗するのは回帰。silent フォールバックを選択（設定画面に説明文を併記）。

## 結果

- 受け入れテスト: `AcceptanceDefaultSessionBackendTests`（6件）・`AcceptanceStartAreaPolicyTests`（3件）を凍結。旧挙動（pty 既定）前提の既存テスト2件は検証意図を保って追随（レビューで弱体化なしを確認）。
- 既知の UI ニュアンス: プロジェクト**名前**クリックは既存挙動どおりグリッド表示へ切り替わる（選択も設定される）。ビューを変えずに選択だけしたい場合はプロジェクト**アイコン**をクリックする。グリッド絞り込み解除後も選択ハイライトが残る点はレビュー LOW（意図確認待ち）。（更新 2026-07-15: single モードでは名前クリックがグリッドへ切り替わらず、プロジェクトを選択して新規セッション開始画面を出すよう変更した。→ ADR 0086）
