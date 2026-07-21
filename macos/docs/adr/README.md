---
status: active        # active | completed | superseded | archived
last-verified: 2026-07-17
---

# ADR（アーキテクチャ決定記録）索引

決定の **理由** を残す。追記専用・不変。覆す時は新しい番号で起こし、旧を `superseded` にしてリンクする。

- 命名: `NNNN-短い決定名.md`（4 桁ゼロ詰め kebab-case。例: `0001-choose-datastore.md`）

## 一覧
| 番号 | 決定 | ステータス |
|---|---|---|
| 0110 | [ターン途中 flush（leading-edge スロットル）と終了時の並行 flush + timeout race](0110-midturn-flush-and-termination-race.md) | active |
| 0109 | [サブエージェントへのフォローアップはメインセッション経由の通常ターンで送る](0109-subagent-followup-via-main-session.md) | active |
| 0108 | [圧縮中インジケーターの開始検知は手動 /compact のみ（stream-json に開始シグナルが無い）](0108-compacting-indicator-manual-only-start.md) | active |
| 0107 | [AskUserQuestion 到着は hasUnseenCompletion ラッチで attention 化する（status は拡張しない）](0107-user-question-attention-latch.md) | active |
| 0106 | [完了サブエージェントの transcript は parsed（永続）を優先する](0106-subagent-transcript-completed-prefers-parsed.md) | active |
| 0105 | [サブエージェント完了レポートの dedup を空白非依存にする](0105-subagent-report-dedup-whitespace-insensitive.md) | active |
| 0104 | [スラッシュコマンドの発火位置を空白区切りトークン先頭に統一（@ と対称）](0104-composer-slash-trigger-position.md) | active |
| 0103 | [質問カードの iOS ミラー配線（wire DTO・POST /question・App 層 witness）](0103-user-question-wire-mirror.md) | accepted |
| 0102 | [AskUserQuestion を CLI control protocol（can_use_tool 中継）で実装する](0102-ask-user-question-control-protocol.md) | accepted |
| 0096 | [チャットのツールコール連続表示のグループ集約と identity 設計](0096-chat-tool-call-grouping.md) | active |
| 0095 | [Codex app-server の error 通知の終端性判定（willRetry 非終端＋EOF 合成終端）](0095-codex-app-server-error-terminality.md) | active |
| 0094 | [グリッドタイルの transcript 窓分化（40件）と hangAssessment 1Hz の viewport 停止](0094-grid-tile-transcript-window-and-hang-timer-pause.md) | active |
| 0093 | [ストリーミング delta のコアレシング適用（イベント毎の即時 UI 無効化を廃止）](0093-transcript-stream-delta-coalescing.md) | active |
| 0092 | [モバイル接続プロキシの Tailscale 遅延起動に対する自己回復（オンデマンド再解決＋起動後リトライ）](0092-mobile-proxy-self-heal-on-tailscale-late-start.md) | active |
| 0091 | [Claude のコンテキスト占有量は「最新リクエスト」で近似する（ターン累積ではない）](0091-claude-context-occupancy-latest-request-not-cumulative.md) | active |
| 0090 | [両サイドバー表示のペイン幅クランプと狭幅カード縦積みのレイアウト方針](0090-dual-sidebar-pane-width-clamp-and-card-stacking.md) | active |
| 0089 | [phlox.cc をモノレポの site/ から GitHub Actions Pages で配信](0089-phlox-cc-served-from-monorepo-site.md) | active |
| 0088 | [接続確立を QR ペアリングに一本化し、手動の認証情報入力・供給 UI を撤去する](0088-qr-only-pairing-remove-manual-token-entry.md) | active |
| 0087 | [モバイル wave-2 ワイヤ拡張（spawn 時モデル適用・プロジェクト付与・エージェント別モデル一覧・アカウント使用量）の設計判断](0087-mobile-wave2-wire-extensions.md) | active |
| 0086 | [single モードのサイドバー・プロジェクト名選択で新規セッション開始画面を表示する](0086-single-mode-project-select-shows-start-screen.md) | active |
| 0085 | [モバイル向けモデル選択 API（GET settings / POST model）](0085-mobile-model-selection-api.md) | active |
| 0084 | [グリッドビューの N×N 固定化・セッション自由配置・セル結合](0084-grid-view-fixed-nxn-free-placement-merge.md) | active |
| 0083 | [非フォーカス時 esc の中止到達と、中断後 transport の turnStart 自己修復](0083-chat-esc-interrupt-unfocused-and-transport-respawn.md) | active |
| 0082 | [空状態カード＋「＋」メニューで agent × mode を明示選択（Pattern A）](0082-agent-mode-launch-cards-and-menu.md) | active |
| 0081 | [「処理中」判定の単一正本化と interrupt の合流・世代ガード](0081-processing-predicate-unification-and-interrupt-coalescing.md) | active |
| 0080 | [アゴラ討論を「完全自由発言（idle ゲート付きリレー）」で実装する](0080-agora-free-speech-discussion.md) | active |
| 0079 | [モバイル向け Control API 拡張（interrupt/subagents/usage/images/差分取得）の設計判断](0079-mobile-api-extensions-design.md) | active |
| 0078 | [チャット composer footer は幅駆動の3段階適応レイアウトにする](0078-composer-adaptive-footer-layout.md) | active |
| 0077 | [サブエージェント transcript のストリーミング断片を itemId で結合する](0077-subagent-transcript-fragment-merge.md) | active |
| 0076 | [モバイルのペアリングに QR コードを採用する](0076-adopt-qr-pairing-for-mobile.md) | active |
| 0075 | [サーバー→モバイルの通知経路として APNs を採用する](0075-adopt-apns-for-mobile-notifications.md) | active |
| 0074 | [モバイル遠隔操作は Tailscale 前提の pull 型 ControlServer API として扱う](0074-mobile-remote-control-design.md) | active |
| 0073 | [前面オーバーレイ UI は「実測高からの余白予約」で本文と重ねない](0073-overlay-inset-by-measured-height.md) | active |
| 0072 | [チーム表示を「アゴラ」に改称し、ツリー埋め込みを廃してフラットグループチャットにする](0072-agora-flat-group-chat.md) | active |
| 0071 | [新規セッションの既定をチャット（appServer）にし、設定で選択可能にする](0071-default-session-backend-chat.md) | active |
| 0070 | [エージェントビュー（チーム表示）をグループチャット＋ツリー埋め込みへ再設計する](0070-agent-view-group-chat.md) | superseded (→0072) |
| 0069 | [ブランチ picker は present-after-load 状態機械で提示し、提示中の popover 内容変更を構造的に禁止する](0069-branch-picker-present-after-load.md) | active |
| 0068 | [終了シグナルハンドラは @Sendable 受け取りの公開 API で isolation 継承を型レベルで遮断する](0068-signal-handler-sendable-isolation.md) | active |
| 0067 | [Thinking インジケータのシマーアニメーションと viewport pause](0067-thinking-wave-animation-and-viewport-pause.md) | active |
| 0066 | [コンテキスト使用量はセッション単位のサイドカー snapshot で永続化する](0066-chat-context-usage-snapshot-persistence.md) | active |
| 0065 | [チャット入力欄をフローティング化し、スクロール逃し余白はコンテンツ内スペーサーで確保する](0065-chat-floating-composer-scrollbar.md) | active |
| 0064 | [処理中インジケータは status を変えず表示専用述語で拡張する](0064-chat-processing-indicator-semantics.md) | active |
| 0063 | [@ファイル補完は TCC 保護フォルダを「実パス一致」で除外する](0063-composer-suggestion-tcc-protected-folders.md) | active |
| 0062 | [チャットのコンテキスト使用率は result/modelUsage と tokenUsageUpdated から実値供給する](0062-chat-context-usage-source.md) | active |
| 0061 | [チャットモードの Claude Usage は常駐プロセスへの `get_usage` 相乗りで供給し、`/usage` プローブを廃止する](0061-claude-usage-get-usage-piggyback.md) | active |
| 0060 | [送信済みチャットメッセージの画像添付は「メタのみ永続・バッジ表示」とする](0060-chat-user-attachment-metadata.md) | active |
| 0059 | [チャットモードの Claude Usage は `/usage` ヘッドレスプローブで供給する](0059-claude-usage-headless-probe.md) | superseded (0061) |
| 0058 | [API spawn の総セッション数上限（16）を撤廃する](0058-remove-api-spawn-total-session-cap.md) | active |
| 0057 | [`FilePatchChange` の wire デコード型とドメイン型を分離したまま据え置く（R4-1）](0057-filepatchchange-wire-vs-domain-type-separation.md) | active |
| 0056 | [状態役割の命名語彙基準（R5）](0056-state-role-naming-vocabulary.md) | active |
| 0055 | [`AppBootstrap → DashboardFeature` 一方向依存の妥当性評価（R3）](0055-appbootstrap-dashboardfeature-dependency-evaluation.md) | active |
| 0054 | [openpty(3) 呼び出しのプロセス内直列化（並列 PTY 割当レースの根治）](0054-ptykit-openpty-serialization.md) | active |
| 0053 | [@ サジェスト走査の背景化と coalescing（in-flight 1本＋最新 pending 1枠）](0053-composer-suggestion-background-coalescing.md) | active |
| 0052 | [チャットセル派生値の内容キー・メモ化（非観測 NSCache）と FileChange 純導出](0052-chat-cell-content-keyed-memoization.md) | active |
| 0051 | [トランスクリプトの末尾 N 件描画（TranscriptWindow・reveal-on-jump・展開アンカー保持）](0051-transcript-tail-window.md) | active |
| 0050 | [Control API の操作認可は「変更系のみ祖先/自己」、read は operator モデル](0050-control-operation-authorization-scope.md) | active |
| 0049 | [hook POST を token↔session 検証で認証する](0049-hook-post-authentication-token-session.md) | active |
| 0048 | [メッセージ DB の migration はスキーマ形状で判定し、30 日保持ポリシーを導入する](0048-message-db-shape-based-migration-and-retention.md) | active |
| 0047 | [セッション機密（token・秘密系 env）を sessions.json へ平文永続化しない](0047-session-secrets-not-persisted-to-sessions-json.md) | active |
| 0046 | [入力欄デフォルト高の「80px」はパネル全体の見た目高さと解釈し、エディタ・余白・フッターを一括圧縮する](0046-composer-default-height-compact-revert.md) | active |
| 0045 | [チャット Markdown 表スタイルから .fixedSize を外し、リサイズ時のレイアウト非収束ループを解消する](0045-remove-fixedsize-from-chat-table-styles.md) | active |
| 0044 | [実行中インジケータを全撤去し、入力欄のデフォルト高を80pxに統一する](0044-remove-running-indicators-composer-80px.md) | active（80px 部分は 0046 で supersede） |
| 0043 | [チームビュー（統合タイムライン）でメイン＋サブエージェントの会話を1本に可視化する](0043-team-view-unified-timeline.md) | superseded (→0070) |
| 0042 | [UI カラースキーマをモノクロ基調＋Claude コーラル単一アクセントへ刷新し、ライトテーマとシームレスなセッション chrome を導入する](0042-monochrome-coral-ui-overhaul.md) | active |
| 0041 | [Gemini / OpenCode / Goose の CLI サポートを削除し、既定 CLI を Claude/Codex/Cursor の3種に限定する](0041-remove-gemini-opencode-goose-clis.md) | active |
| 0040 | [チャットの履歴再開は ~/.claude/projects の JSONL 直読み＋off-main リアクティブロード](0040-chat-history-resume-from-claude-projects.md) | active |
| 0039 | [Claude Usage の供給はターミナル限定と認め、行を消さず鮮度を可視化](0039-claude-usage-statusline-terminal-only.md) | active |
| 0038 | [チャットのターンコストは turnUsage イベントで運搬し USD 表示](0038-chat-turn-cost-via-turnusage-event.md) | active |
| 0037 | [チャット自動追従の離脱判定をオフセット推測からユーザー操作イベント駆動へ](0037-chat-autofollow-event-driven-detach.md) | active |
| 0036 | [グリッド入力欄の auto-grow 再有効化と ComposerHeightBounds 単一真実源](0036-grid-composer-autogrow-reenable.md) | active |
| 0034 | [Release/Debug 同時併用を AppFlavor 分離で実現する](0034-release-debug-coexistence-via-app-flavor.md) | active |
| 0032 | [エージェントのブランドアイコンは xcassets+SVG（actool）で組み込む——swift test では描画されない制約込み](0032-brand-icons-xcassets-svg-and-swift-test-actool-gap.md) | active |
| 0031 | [チャット履歴リバートは「ローカル転写の切り詰め＋会話リセット＋文脈リプレイ」で実現する](0031-chat-history-revert-via-local-truncation-and-context-replay.md) | active |
| 0030 | [トランスクリプトの非遅延レイアウト化と composer 計測の一方向化（CPU 暴走根治）](0030-transcript-eager-layout-and-one-way-composer-metrics.md) | active |
| 0029 | [チャット入力欄（composer）フッター再設計と borderlessButton Menu のホバー/描画制約への対処](0029-chat-composer-footer-redesign-and-borderless-menu-hover.md) | active |
| 0028 | [Cursor のシェルスナップショット・デッドロック回避（cursor 限定 ZDOTDIR）と OneShotProcessRunner ウォッチドッグ](0028-cursor-shell-snapshot-deadlock-zdotdir-and-oneshot-watchdog.md) | active |
| 0027 | [グリッドのワークスペース絞り込みは orchestration サブセッションを含める（サーフェス別の可視性ルール分離）](0027-grid-workspace-filter-includes-subsessions.md) | active |
| 0026 | [チャットモードのオーケストレーション対等化（spawn / backend 継承 / wait 完了検知）](0026-chat-mode-orchestration-parity.md) | active |
| 0025 | [サブエージェント別チャットの隔離・表示・transcript 組立](0025-subagent-chat-isolation-display-and-transcript-assembly.md) | active |
| 0024 | [復元中の破壊的永続化ゲートと Commands の disabled 条件規約](0024-restore-gate-and-commands-reactivity.md) | active |
| 0023 | [チャット自動追従スクロールの非アニメ化（自己持続再無効化ループの遮断）](0023-chat-autofollow-scroll-deanimation.md) | active |
| 0022 | [中断の後始末を中立化し、self-heal を双方向＋ターン内上限つきに拡張する](0022-claude-chat-interrupt-neutralization-and-bidirectional-heal.md) | active |
| 0021 | [Claude チャットの respawn 引数選択と resume 失敗の self-heal](0021-claude-chat-respawn-selection-and-self-heal.md) | active |
| 0019 | [UI を Apple Liquid Glass へ刷新する（機能層限定・macOS 26 条件採用）](0019-liquid-glass-ui-adoption.md) | active |
| 0018 | [Cursor 会話継続の native session id を Cursor 限定で永続化する](0018-cursor-native-session-id-writeback-gated.md) | active |
| 0017 | [構造化チャットの承認ゲート配線とツール承認の粒度（turn 単位）](0017-structured-chat-approval-gate-and-turn-granularity.md) | active |
| 0016 | [全 appServer backend で表示用 transcript を Phlox 側永続化へ統一する](0016-unified-transcript-persistence-across-appserver-backends.md) | active |
| 0015 | [端末描画からの脱却 — 複数 CLI 共通の構造化チャットバックエンド](0015-structured-chat-backend-multi-cli.md) | active |
| 0013 | [セッション削除をサブツリー・カスケード化（子孫の reparent を廃止）](0013-cascade-session-deletion-subtree.md) | active |
| 0012 | [claudeCode の resumeID を claude のネイティブ session id へ on-change 追従](0012-claudecode-resumeid-native-followup.md) | active |
| 0010 | [描画中の @Observable 変更による再無効化ループの回避（普遍的 SwiftUI 教訓）](0010-loopflow-kanban-hang-observable-mutation-during-render.md) | active |
| 0009 | [子プロセスのライフサイクル堅牢化（孤児化防止）](0009-child-process-lifecycle-hardening.md) | active |
| 0004 | [セッション kill の所有者認可とガイド配信の kind 別化](0004-session-kill-authorization-and-guide-delivery.md) | active |
| 0001 | [Agent Dashboard アーキテクチャ](0001-architecture.md) | active |
| 0000 | （雛形） | template |
