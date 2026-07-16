---
status: active
last-verified: 2026-07-12
---

# ADR 0082: 空状態カード＋「＋」メニューで agent × mode を明示選択（Pattern A）

> **このファイルの役割**: なぜ新規セッション作成 UI を「エージェント選択 → その後モード選択」の多段導線から、カード／メニュー上で agent × mode を1画面・最小アクションで選ぶ形（Pattern A）へ変えたかの決定。
> **書かないもの**: カード/メニューの現行構成（→ `architecture/dashboard-empty-state-agent-cards.md`・`architecture/team-timeline-view.md`）、既定バックエンドの決定（→ ADR 0071）、structured chat 対応の仕組み（→ ADR 0015）。

## 文脈

ADR 0071 で新規セッションの既定バックエンドをチャット（appServer）にしたが、**モードの選択操作自体は UI に露出していなかった**。ターミナルで開きたいときは設定画面で既定を切り替えるか、「＋」メニューのネストした `Menu`（エージェント → その中で Terminal/Chat）を辿る必要があり、空状態カードは「1タップ＝既定バックエンドで spawn」だけでモードを選べなかった。ユーザー指摘（2026-07-12 UX 議論）: 「ターミナルかチャットを開くのに最低3アクション（＋ボタン → エージェント選択 → モード選択）かかる／カードからモードを選べない」。

チャットとターミナルは描画パイプラインが根本的に異なる（appServer=構造化イベントの SwiftUI 描画 / pty=SwiftTerm の生バイト描画）ため、起動後のライブ・トグルは非現実的で、**作成時に agent × mode を選ぶ**のが妥当と確認した。

## 決定

1. **Pattern A（big-buttons split-card）採用**: 空状態カードを「エージェント（アイコン＋名前）＋下段にモード2ボタン」の構成にする。チャットボタンをエージェント色で濃いめに描き**既定として微強調**、ターミナルボタンは控えめに併置する。1カード内で agent と mode を同時に選べる（最小アクション化）。
2. **「＋」メニューのフラット化**: `DashboardView.newSessionMenuItems` とチームビュー `TeamTimelineView`（非討論時）の「＋」を、ネスト `Menu` から `descriptor × modes(for:)` のフラット項目（「<表示名> — チャット/ターミナル」）へ変える。
3. **モード出し分けは `supportsStructuredChat`**: `AgentStartCardsModel.modes(for:)` が対応エージェントに `[.chat, .terminal]`、非対応に `[.terminal]` を返す。非対応エージェントにチャット導線を出さない。
4. **backend 写像の単一化**: `AgentStartCardMode.backend`（chat→`.appServer` / terminal→`.pty`）に集約し、spawn は既存 `createSession(ref:projectID:backend:)` 経路をそのまま使う（新規 spawn 経路を作らない）。

## 棄却案

- **設計検討した他導線**: モード先選択（mode-first）／agent×mode マトリクス／コマンドパレット風／プライマリ・セカンダリ分割（refine A–D 各種）。カードの空間効率・発見性・「チャット既定を強調しつつターミナルを1タップ差で出せる」点から Pattern A（big-buttons split-card）を採用。
- **起動後のライブ・トグル**: チャット/ターミナルは描画パイプラインが別で、同一セッションの往復切替は状態・描画を破棄する必要があり非現実的。作成時選択に限定。
- **素のターミナル（エージェント無し）モードの追加**: 今回のスコープ外。ターミナルモードは従来どおり選択エージェントを pty で開く。

## 結果

- 受け入れテスト: `AcceptanceAgentModeLaunchTests`（backend 写像・chat 対応エージェントのモード列挙）・`AcceptanceAgentStartCardsTests` を凍結。白箱 `AgentModeLaunchWhiteboxTests`（非対応エージェントのターミナルのみ）追加。`swift test`（DashboardFeature）1311 件・ヘッドレス E2E 15 件 green。
- 既知の積み残し: 旧「＋」メニューが使っていた `DashboardViewModel.defaultBackendForGUISpawn(ref:)` が本変更で孤児化（モードは `mode.backend` 直接指定へ移行）。allowed_paths 外のため本 run では除去せず、後続タスクで削除予定。
- ADR 0071（既定チャット化）を UI 導線の面で具体化する位置づけ。既定バックエンド自体の決定は 0071 が正本。
