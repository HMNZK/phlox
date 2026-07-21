import Foundation
import AgentDomain
import HookServer
import PTYKit
import TerminalUI
import Observation

/// 1 つの Claude Code セッションの状態を保持し、Hook イベントを購読して `SessionStatus` を更新する。
/// PTY 出力は SwiftTerm に直接 feed するため、本 VM は通さない（フレーム落ち回避）。
///
/// API 契約 (M6a で本実装、M6b は本シグネチャに依存):
/// - `init` の引数を変更しないこと
/// - public プロパティ / メソッドの追加は可、削除・名称変更は不可
@MainActor
@Observable
public final class SessionViewModel: Identifiable {
    public let id: SessionID
    public let startedAt: Date
    public private(set) var status: SessionStatus
    public let terminalCoordinator: TerminalCoordinator
    public var name: String = ""
    /// 所属ワークスペース（内部は Project）。生成後に DashboardViewModel が代入する。
    public var projectID: ProjectID?
    /// API spawn の親セッション。kill 認可と深さ判定の単一ソース。
    public var parentSessionID: SessionID?
    /// 起動経路。orchestration はサイドバー非表示だが内部参照は可能。
    public var launchContext: SessionLaunchContext = .interactive
    public private(set) var hasProducedOutput = false
    public private(set) var lastOutputAt: Date?
    public private(set) var lastTurnCompletedAt: Date?
    public private(set) var submitBaselineTurnSeq: Int?
    public private(set) var completedTurnSeq: Int = 0
    public private(set) var activeTurnId: String?
    public private(set) var isRestored = false
    public var hasUnseenCompletion: Bool = false {
        didSet {
            guard oldValue != hasUnseenCompletion else { return }
            unseenCompletionDidChange?()
        }
    }
    @ObservationIgnored public var unseenCompletionDidChange: (() -> Void)?
    @ObservationIgnored public var onInputSubmitted: (() -> Void)?
    @ObservationIgnored public var eventSink: ((SessionID, SessionStatus, Date) -> Void)?
    /// リモート通知系へのフック。nil なら呼ばれない（既存挙動と同一）。
    @ObservationIgnored public var remoteSessionNotifier: (any RemoteSessionNotifier)?

    /// 初回出力後、この秒数アイドルしてから入力準備完了とみなす（全 CLI 共通の settle）。
    static let inputReadinessSettleSeconds: TimeInterval = 0.4
    private static let inputReadinessSettleDuration: Duration = .milliseconds(400)

    public var isReadyForInput: Bool {
        switch spawnRequest.statusBootstrap {
        case .viaHook:
            // SessionStart フック受信（.starting 脱出）が必須。さらに起動描画が静止する
            // まで待つ（SessionStart が TUI の入力受付より早く発火する場合の保険）。
            // 初回出力だけで ready にすると、TUI 起動完了前に書き込まれた入力が破棄される。
            // SessionStart 不達のフォールバックは置かない: hooks は Phlox 自身が --settings で
            // 注入しており、不達は status 系全体の故障。timeout で ready:false を返すのが正直。
            return status.isReadyForInput && hasSettledOutput
        case .idleOnSpawnComplete:
            return hasSettledOutput
        }
    }

    /// 初回出力済みかつ最終出力から settle 秒静止したか。起動描画の完了の近似。
    private var hasSettledOutput: Bool {
        guard hasProducedOutput, let lastOutputAt else { return false }
        return Date().timeIntervalSince(lastOutputAt) >= Self.inputReadinessSettleSeconds
    }

    /// 行に出す表示名。name が空白のみなら shortID をフォールバック。
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? Self.shortID(for: id) : trimmed
    }

    public static func shortID(for id: SessionID) -> String {
        "#" + id.rawValue.uuidString.prefix(6)
    }

    /// ターミナルがレイアウト確定したあと PTY を起動するための spawn パラメータ。
    public struct SpawnRequest: Sendable {
        public let command: String
        public let args: [String]
        public let env: [String: String]
        public let workingDirectory: String?
        public let agentDescriptor: AgentDescriptor
        public let statusBootstrap: StatusBootstrap
        public let postSpawnReset: PostSpawnReset?
        public let debugDump: Bool

        public init(
            command: String,
            args: [String],
            env: [String: String],
            workingDirectory: String?,
            kind: AgentKind = .claudeCode,
            agentDescriptor: AgentDescriptor? = nil,
            statusBootstrap: StatusBootstrap = .viaHook,
            postSpawnReset: PostSpawnReset? = nil,
            debugDump: Bool = false
        ) {
            self.command = command
            self.args = args
            self.env = env
            self.workingDirectory = workingDirectory
            self.agentDescriptor = agentDescriptor ?? AgentRegistry.descriptor(for: kind)
            self.statusBootstrap = statusBootstrap
            self.postSpawnReset = postSpawnReset
            self.debugDump = debugDump
        }
    }

    /// このセッションが起動した CLI の種類。
    public var agentRef: AgentRef { spawnRequest.agentDescriptor.ref }
    public var agentDescriptor: AgentDescriptor { spawnRequest.agentDescriptor }
    public var agentKind: AgentKind { spawnRequest.agentDescriptor.kind }

    /// 現在のワークスペース (CWD) の末尾ディレクトリ名。一覧・グリッドの簡易表示用。
    /// restart で workingDirectory が差し替わると spawnRequest 経由で自動的に更新される。
    public var workspaceName: String {
        guard let dir = spawnRequest.workingDirectory, !dir.isEmpty else { return "" }
        return (dir as NSString).lastPathComponent
    }

    /// 現在のワークスペース (CWD) のフルパス（ホームを ~ に短縮）。ツールチップ等の詳細表示用。
    public var workspacePath: String {
        guard let dir = spawnRequest.workingDirectory, !dir.isEmpty else { return "" }
        return (dir as NSString).abbreviatingWithTildeInPath
    }

    private let ptyManager: any PTYManagerProtocol
    // restart 時に新 hook stream / 新 workingDirectory へ差し替えるため var とする
    // （API 契約上 private メンバーの let→var 化は許容）。
    private var hookEvents: AsyncStream<(SessionID, HookEvent)>
    private var spawnRequest: SpawnRequest
    private var didSpawn = false
    /// PTY spawn の await が成功して fd が有効になったあと true。spawn 中 (didSpawn=true,
    /// didSpawnComplete=false) に handleResize が PTY resize を呼ぶと未登録 fd で silently
    /// 失敗するため、その間の resize は pendingResize に退避して spawn 完了後に反映する。
    private var didSpawnComplete = false
    private var pendingResize: (cols: UInt16, rows: UInt16)?
    /// 初回 spawn の trailing debounce 用。起動直後はサイドバー開閉アニメーション等で
    /// ターミナル幅が連続変化するため、最後の sizeChanged から一定時間静止してから
    /// 確定サイズで 1 回だけ spawn する。途中幅での spawn→resize 連発を避ける。
    private var initialSpawnTask: Task<Void, Never>?
    private var initialSpawnSize: (cols: UInt16, rows: UInt16)?
    /// 初回 spawn を遅延させる静止待ち時間。サイドバー開閉アニメーション(0.18s)の
    /// 連続フレームを束ね、終了後の確定サイズで spawn できる程度に設定する。
    private static let initialSpawnDebounce: Duration = .milliseconds(150)
    /// spawn 世代カウンタ。restart で再 spawn する度にインクリメントする。exitTask は起動時の
    /// 世代を捉え、status 反映前に現在世代と一致するか確認することで、旧世代プロセスの遅延 exit に
    /// よる汚染を防ぐ（Task.cancel の伝播レースに依存しない決定論的ガード）。
    private var spawnEpoch = 0

    private var outputTask: Task<Void, Never>?
    private var hookTask: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?
    private let nonHookIdleFallbackTracker: NonHookIdleFallbackTracker
    /// codex セッションのときだけ生成される CLI 固有処理（信頼プロンプト自動応答・質問検知）。
    /// agentRef は restart でも変わらないため init で確定する。
    private let codexAdapter: CodexSessionAdapter?
    /// codex 出力評価の debounce 間隔。出力チャンク毎に O(rows×cols) の visibleText() 構築を
    /// @MainActor で行わないよう、最後の出力からこの時間静止したあとに 1 回だけ評価する。
    /// テストから決定的に制御できるよう内部可視で差し替え可能。
    var codexOutputDebounceInterval: Duration = .milliseconds(75)
    /// sendText の本文書込から submit キー(\r)送出までの待ち時間。codex TUI はペースト
    /// バースト判定後 120ms の Enter 抑制窓を持ち(paste_burst.rs の
    /// PASTE_ENTER_SUPPRESS_WINDOW)、この間に届いた \r は送信でなく改行として扱われる。
    /// そのため 120ms より十分大きい値にする。テストから差し替え可能なよう内部可視 var。
    var submitKeyDelay: Duration = .milliseconds(250)
    private var codexOutputEvaluationTask: Task<Void, Never>?
    /// debounce の世代カウンタ。新しい出力チャンクが来るたびに進め、旧タスクの遅延発火を無効化する。
    private var codexOutputEvaluationGeneration = 0

    /// codex への submit 後、処理状態(turn 開始)へ入ったかを観測する計装(ADR 0002 §8.6)。
    /// 一定時間内に処理開始を一度も観測できなければ submit 滞留の疑いとして診断ログに残す。
    /// **observe-only**: status / completedTurnSeq は一切変えない(完了誤検知の本修正は別タスク)。
    /// テストから差し替え可能なよう内部可視 var。
    var submitTurnStartTimeout: Duration {
        get { submitDiagnosticRecorder.timeout }
        set { submitDiagnosticRecorder.timeout = newValue }
    }
    private let submitDiagnosticRecorder: SubmitDiagnosticRecorder
    /// 診断行の出力先。既定はログファイル追記。テストから capture 用に差し替える(実 I/O 回避)。
    var submitDiagnosticSink: @MainActor (String) -> Void {
        get { submitDiagnosticRecorder.sink }
        set { submitDiagnosticRecorder.sink = newValue }
    }
    /// submit 後に codex の「処理中」を観測済みか（テストの決定的待機用の読み取りシーム）。
    /// true を確認できれば、以後 flush は診断を発火しない（observedProcessing は再 arm まで不変）。
    var hasObservedSubmitProcessingForTesting: Bool {
        submitDiagnosticRecorder.hasObservedProcessing
    }

    public init(
        id: SessionID,
        startedAt: Date = Date(),
        ptyManager: any PTYManagerProtocol,
        hookEvents: AsyncStream<(SessionID, HookEvent)>,
        terminalCoordinator: TerminalCoordinator,
        spawnRequest: SpawnRequest
    ) {
        self.id = id
        self.startedAt = startedAt
        self.status = .starting
        self.ptyManager = ptyManager
        self.hookEvents = hookEvents
        self.terminalCoordinator = terminalCoordinator
        self.spawnRequest = spawnRequest
        self.nonHookIdleFallbackTracker = NonHookIdleFallbackTracker(
            settleDuration: SessionViewModel.inputReadinessSettleDuration
        )
        self.codexAdapter = spawnRequest.agentDescriptor.ref == .builtin(.codex) ? CodexSessionAdapter() : nil
        self.submitDiagnosticRecorder = SubmitDiagnosticRecorder(
            sessionLabel: Self.shortID(for: id),
            agentKind: { spawnRequest.agentDescriptor.kind },
            visibleText: { terminalCoordinator.visibleText() }
        )
        bindCoordinator()
    }

    /// M6a で実装。Hook イベントの購読を開始する。PTY spawn と終了監視 (exitTask) は
    /// `spawnIfNeeded` で遅延する。exitTask を spawn 後に張る理由は spawnIfNeeded のコメント参照。
    public func start() async {
        let events = hookEvents

        hookTask = Task { @MainActor [weak self] in
            for await (sessionID, event) in events {
                guard let self, sessionID == self.id else { continue }
                let timestamp = Date()
                let previousStatus = self.status
                let nextStatus = reduce(previousStatus, applying: event)
                self.transitionStatus(to: nextStatus, at: timestamp)
                self.reconcileCodexQuestionStatus()
                let finalStatus = self.status
                self.notifyCompletionIfNeeded(from: previousStatus, to: finalStatus)
                self.cancelNonHookIdleFallbackIfNeeded(for: finalStatus)
                switch event {
                case .userPromptSubmit(let turnId):
                    if let turnId {
                        self.activeTurnId = turnId
                    }
                case .stop(let turnId):
                    guard !finalStatus.isAwaitingApproval else { break }
                    if let turnId {
                        if turnId == self.activeTurnId {
                            self.completedTurnSeq += 1
                            self.lastTurnCompletedAt = Date()
                        }
                    } else {
                        self.completedTurnSeq += 1
                        self.lastTurnCompletedAt = Date()
                    }
                default:
                    break
                }
            }
        }
    }

    /// View が attach され SwiftTerm のサイズが確定したときに spawn する（debounce 経由）。
    /// eager spawn 済みのときは spawnOnce 内の didSpawn ガードで no-op になる。
    public func spawnIfNeeded(initialCols: UInt16, initialRows: UInt16) async {
        await spawnOnce(cols: initialCols, rows: initialRows)
    }

    /// View の描画・レイアウト確定を待たず、既定 winsize で即座に PTY を起動する。
    /// API 経由 spawn など「表示されていないセッション」でもプロセスを起動させるための eager 経路。
    /// View 出現後の sizeChanged は handleResize の resize 分岐が実サイズへ追従する
    /// （codex/cursor は scrollback 無効化済みのため、既定サイズ→実サイズの resize でも
    /// ゴーストは蓄積しない）。
    public func spawnEager() async {
        // TerminalCoordinator は 800x480 の初期 frame から算出した暫定グリッドを持つ。
        // それを使えば実サイズに近く resize 差分が小さい。0 のときは 80x24 にフォールバック。
        let cols = terminalCoordinator.initialCols
        let rows = terminalCoordinator.initialRows
        await spawnOnce(cols: cols > 0 ? cols : 80, rows: rows > 0 ? rows : 24)
    }

    /// PTY spawn の共通コア。spawnIfNeeded（確定サイズ）と spawnEager（既定サイズ）の双方から呼ぶ。
    /// didSpawn ガードで二重 spawn を防ぐ。exitTask を spawn 後に張る理由は本メソッド末尾参照。
    private func spawnOnce(cols: UInt16, rows: UInt16) async {
        guard !didSpawn else { return }
        didSpawn = true
        // debounce 待機中の初回 spawn タスクがあれば破棄する（eager から呼ばれた場合の保険）。
        initialSpawnTask?.cancel()
        initialSpawnTask = nil

        do {
            _ = try await ptyManager.spawn(
                command: spawnRequest.command,
                args: spawnRequest.args,
                env: spawnRequest.env,
                id: id,
                initialSize: PTYInitialSize(cols: cols, rows: rows),
                workingDirectory: spawnRequest.workingDirectory
            )
        } catch {
            didSpawn = false
            transitionStatus(to: .error(message: "spawn failed: \(error)"), at: Date())
            return
        }

        didSpawnComplete = true

        bootstrapIdleStatusIfNeeded()
        schedulePostSpawnResetIfNeeded()
        await applyPendingResizeIfNeeded()

        let sessionLabel = String(id.rawValue.uuidString.prefix(6))
        let rawCapture = spawnRequest.debugDump
            ? SessionDebugCapture.openRawOutputCapture(sessionLabel: sessionLabel)
            : nil

        // output/exit stream は spawn 後に「同期的に」取得する。spawn で StreamCache に
        // 最新 stream が登録された直後に購読するため、初回・再起動とも最新 stream を掴む
        // （spawn 前に張ると実 PTYManager では未登録 stream を掴んで即 finish する）。
        // 取得を Task の外で行うのは、spawnIfNeeded 完了時点で continuation が確実に
        // 登録されているようにし、直後の exit 発火を取りこぼさないため。
        let outputStream = ptyManager.outputStream(for: id)
        let exitStream = ptyManager.exitStream(for: id)

        // restart で再 spawn する度に世代を進める。exitTask は自分の世代を捉える。
        spawnEpoch += 1
        let epoch = spawnEpoch

        startOutputTask(outputStream: outputStream, rawCapture: rawCapture)

        if spawnRequest.debugDump {
            await SessionDebugCapture.dumpAndScheduleWinsizes(
                sessionID: id,
                sessionLabel: sessionLabel,
                ptyManager: ptyManager,
                terminalCoordinator: terminalCoordinator,
                isSessionAlive: { [weak self] in self != nil }
            )
        }

        startExitTask(exitStream: exitStream, epoch: epoch)
    }

    /// Codex/Cursor は起動時 hooks がないため、spawn 完了をもって idle とみなす。
    private func bootstrapIdleStatusIfNeeded() {
        guard case .idleOnSpawnComplete = spawnRequest.statusBootstrap, status == .starting else { return }
        let timestamp = Date()
        let previousStatus = status
        transitionStatus(to: .idle, at: timestamp)
        notifyCompletionIfNeeded(from: previousStatus, to: status)
    }

    /// Phase 6a リカバリ: 通常バッファ TUI の 2 段階描画後の整列のため、
    /// 内部 buffer クリア + SIGWINCH で再描画を促す。
    private func schedulePostSpawnResetIfNeeded() {
        guard case .refreshTerminalAndSIGWINCH(let delay) = spawnRequest.postSpawnReset else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            let cols = self.terminalCoordinator.currentCols
            let rows = self.terminalCoordinator.currentRows
            self.terminalCoordinator.resetBuffer()
            try? await self.ptyManager.resize(self.id, cols: cols, rows: rows)
        }
    }

    /// spawn 中に来ていた最新 size を反映 (4→5 セッション遷移などで spawn と
    /// 既存タイル column shrink が競合した時、Claude Code を新サイズで起動させる)
    private func applyPendingResizeIfNeeded() async {
        guard let pending = pendingResize else { return }
        pendingResize = nil
        try? await ptyManager.resize(id, cols: pending.cols, rows: pending.rows)
    }

    /// PTY 出力の購読タスクを張る。SwiftTerm への feed・出力観測フラグの更新・
    /// codex 固有評価のトリガと、debugDump 時の生出力キャプチャを行う。
    private func startOutputTask(
        outputStream: AsyncStream<Data>,
        rawCapture: SessionDebugCapture.RawOutputCapture?
    ) {
        let coordinator = terminalCoordinator

        outputTask = Task { @MainActor [weak self] in
            defer { rawCapture?.close() }

            for await data in outputStream {
                if self?.hasProducedOutput == false {
                    self?.hasProducedOutput = true
                }
                let outputAt = Date()
                self?.lastOutputAt = outputAt
                coordinator.feed(data)
                self?.scheduleCodexOutputEvaluation()
                self?.observeNonHookOutputIfNeeded(at: outputAt)
                rawCapture?.write(data)
            }
        }
    }

    /// PTY exit の購読タスクを張る。
    private func startExitTask(exitStream: AsyncStream<Int32>, epoch: Int) {
        exitTask = Task { @MainActor [weak self] in
            for await code in exitStream {
                // 旧世代の exitTask が旧プロセスの遅延 exit を拾って新セッションの status を
                // 汚染しないよう、起動時の世代が現在世代と一致するときだけ反映する
                // （Task.cancel の伝播レースに依存しない決定論的ガード）。
                guard let self, self.spawnEpoch == epoch else { return }
                let timestamp = Date()
                if code == 0 {
                    self.transitionStatus(to: .completed(exitCode: 0), at: timestamp)
                } else {
                    self.transitionStatus(to: .error(message: "exit code \(code)"), at: timestamp)
                }
            }
        }
    }

    /// 送信直後に呼び、次ターンの userPromptSubmit 待ち状態にする。
    /// send と userPromptSubmit の隙間に来た古い Stop が誤マッチしないようにする。
    public func markAwaitingNewTurn() {
        activeTurnId = nil
    }

    public func markInputSubmitted() {
        onInputSubmitted?()
        codexAdapter?.noteInputSubmitted()
        guard usesNonHookIdleFallback else { return }
        nonHookIdleFallbackTracker.markInputSubmitted()

        if status == .idle {
            transitionStatus(to: .running, at: Date())
        }
    }

    public func markCompletionSeen() {
        hasUnseenCompletion = false
    }

    /// M6a で実装。ユーザー入力を PTY の stdin に書き込む。
    public func sendInput(_ data: Data) async {
        guard didSpawn else { return }
        if data.containsSubmitKey {
            markInputSubmitted()
        }
        // Claude Code(viaHook) は esc 中断時に stop フックを出さない（公式仕様）ため、
        // running から idle へ戻す経路が無く固着する。Escape キー単体かつ running のときに
        // idle へ整合させる。完了ではなくキャンセルなので完了通知は出さない。万一中断が
        // 成立せず動作継続した場合も、後続の活動フック(postToolUse 等)が running へ戻す。
        if data.isLoneEscape, status == .running, !usesNonHookIdleFallback {
            activeTurnId = nil
            transitionStatus(to: .idle, at: Date())
        }
        try? await ptyManager.write(data, to: id)
    }

    /// 出力チャンク到達のたびに呼び、codex 固有評価（信頼プロンプト自動応答・質問検知）を
    /// debounce 付きで予約する。visibleText() の構築は O(rows×cols) かつ @MainActor のため、
    /// チャンク毎には行わず、最後の出力から `codexOutputDebounceInterval` 静止後に 1 回だけ行う。
    private func scheduleCodexOutputEvaluation() {
        guard codexAdapter != nil else { return }
        codexOutputEvaluationGeneration += 1
        let generation = codexOutputEvaluationGeneration
        codexOutputEvaluationTask?.cancel()
        codexOutputEvaluationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.codexOutputDebounceInterval)
            guard !Task.isCancelled, generation == self.codexOutputEvaluationGeneration else { return }
            self.evaluateCodexOutput()
        }
    }

    /// 静止後の 1 回評価。visibleText() を 1 回だけ構築し、信頼プロンプト自動応答と質問検知で共有する。
    /// 信頼プロンプト検出時は 1 度だけ Enter（既定の Yes, continue）を送って composer まで進める。
    /// これがないと自律 spawn した codex がプロンプトで止まり送信が届かない（ADR 0002）。
    private func evaluateCodexOutput() {
        guard let adapter = codexAdapter else { return }
        let visibleText = terminalCoordinator.visibleText()
        // submit 後の処理開始を出力ごとにサンプリングし、一度でも観測したら成立とみなす
        // (高速ターンの取り逃し対策。observe-only)。
        submitDiagnosticRecorder.observeProcessingIfVisible(in: visibleText)
        if adapter.consumeTrustPromptAutoAnswer(visibleText: visibleText) {
            sendTrustPromptEnter()
        }
        apply(adapter.reconcileQuestion(visibleText: visibleText, status: status))
    }

    /// codex への submit 直後に呼び、処理開始(turn 開始)の観測を始める(observe-only)。
    /// `submitTurnStartTimeout` 内に処理開始を一度も観測できなければ滞留の疑いをログに残す。
    private func armSubmitDiagnostic(byteCount: Int, bracketed: Bool) {
        guard codexAdapter != nil else { return }
        submitDiagnosticRecorder.arm(byteCount: byteCount, bracketed: bracketed)
    }

    /// 信頼プロンプトへの自動応答（Enter = 既定の Yes, continue）を非同期で送る。
    private func sendTrustPromptEnter() {
        let sessionID = id
        Task { @MainActor [weak self] in
            try? await self?.ptyManager.write(Data("\r".utf8), to: sessionID)
        }
    }

    /// hook イベント経路の同期評価。hook による status 遷移（stop→idle 等）が質問表示中の
    /// awaiting を巻き戻さないよう、イベント適用直後にその場で再整合する（低頻度のため debounce しない）。
    private func reconcileCodexQuestionStatus() {
        guard let adapter = codexAdapter else { return }
        let action = adapter.reconcileQuestion(visibleText: terminalCoordinator.visibleText(), status: status)
        apply(action)
    }

    /// adapter の質問検知結果を status 遷移・通知へ適用する。
    private func apply(_ action: CodexSessionAdapter.QuestionAction) {
        switch action {
        case .none:
            break
        case .enterAwaiting(let notifyAwaitingInput):
            cancelNonHookIdleFallback()
            transitionStatus(to: .awaitingApproval(prompt: "Codex is asking a question"), at: Date())
            if notifyAwaitingInput {
                SessionCompletionNotifier.notifyAwaitingInput(sessionName: displayName)
                remoteSessionNotifier?.approvalPending(
                    sessionId: id.description,
                    sessionName: displayName
                )
            }
        case .reassertAwaiting:
            transitionStatus(to: .awaitingApproval(prompt: "Codex is asking a question"), at: Date())
        case .resumeRunning:
            if case .awaitingApproval = status {
                transitionStatus(to: .running, at: Date())
            }
        }
    }

    /// M6a で実装。セッションを終了させる（SIGTERM）。
    public func kill() async {
        initialSpawnTask?.cancel()
        initialSpawnTask = nil
        outputTask?.cancel()
        hookTask?.cancel()
        exitTask?.cancel()
        nonHookIdleFallbackTracker.cancel()
        codexOutputEvaluationTask?.cancel()
        submitDiagnosticRecorder.cancel()
        outputTask = nil
        hookTask = nil
        exitTask = nil
        codexOutputEvaluationTask = nil
        guard didSpawn else { return }
        await ptyManager.kill(id)
    }

    /// ワークスペース (CWD) を変更するため、現プロセスを kill して新 workingDirectory で
    /// PTY を起動し直す。SessionViewModel / TerminalCoordinator のインスタンスは維持するため
    /// SwiftUI のビュー identity と reparent は起きない。進行中の作業は失われる。
    ///
    /// hook stream は AsyncStream の単一コンシューマ前提を守るため、呼び出し側
    /// (DashboardViewModel) が旧 stream を finish し新 stream を生成して引数で渡す。
    public func restart(
        workingDirectory: String,
        hookEvents: AsyncStream<(SessionID, HookEvent)>
    ) async {
        // 1. 旧プロセスを kill し、outputTask/hookTask/exitTask を cancel→nil 化する。
        await kill()

        // 2. 状態リセット。didSpawn を false に戻すことで spawnIfNeeded が再実行できる。
        didSpawn = false
        didSpawnComplete = false
        hasProducedOutput = false
        lastOutputAt = nil
        activeTurnId = nil
        nonHookIdleFallbackTracker.cancel()
        codexAdapter?.reset()
        pendingResize = nil

        // 3. hook stream を新 stream へ差し替える（旧 stream は Dashboard 側で finish 済み）。
        self.hookEvents = hookEvents

        // 4. workingDirectory だけ差し替えた SpawnRequest に再代入（env/command/args は引き継ぐ）。
        spawnRequest = SpawnRequest(
            command: spawnRequest.command,
            args: spawnRequest.args,
            env: spawnRequest.env,
            workingDirectory: workingDirectory,
            agentDescriptor: spawnRequest.agentDescriptor,
            statusBootstrap: spawnRequest.statusBootstrap,
            postSpawnReset: spawnRequest.postSpawnReset,
            debugDump: spawnRequest.debugDump
        )

        // 5. 再起動中を UI に反映する。
        transitionStatus(to: .starting, at: Date())

        // 6. 旧プロセスの描画残骸をクリアする。
        terminalCoordinator.resetBuffer()

        // 7. hookTask を新 hookEvents で張り直す。
        await start()

        // 8. 現グリッドサイズで再 spawn する。spawnIfNeeded 内で outputTask/exitTask が
        //    最新 stream に張り直される。
        let cols = terminalCoordinator.initialCols
        let rows = terminalCoordinator.initialRows
        await spawnIfNeeded(initialCols: cols, initialRows: rows)
    }

    /// 復元準備に失敗した descriptor を UI に残すためのエラー状態をセットする。
    /// spawn は行わず、descriptor は永続化されたまま次回起動で再試行できる。
    public func markRestoreFailed(_ message: String) {
        isRestored = true
        transitionStatus(to: .error(message: message), at: Date())
    }

    private func bindCoordinator() {
        terminalCoordinator.onInput = { [weak self] data in
            Task { await self?.sendInput(data) }
        }
        terminalCoordinator.onResize = { [weak self] cols, rows in
            Task { @MainActor in
                await self?.handleResize(cols: cols, rows: rows)
            }
        }
    }

    private func handleResize(cols: UInt16, rows: UInt16) async {
        if !didSpawn {
            // 初回 spawn のみ trailing debounce する。起動直後のレイアウト確定やサイドバー
            // 開閉アニメーションでターミナル幅が連続変化し、その途中幅で spawn→resize を
            // 繰り返すと、alternate screen を使わない通常バッファの TUI (Cursor/Codex) が
            // 各幅でプロンプトを再描画し、旧描画が scrollback に残ってゴーストになる。
            // サイズが静止してから確定幅で 1 回だけ spawn してこれを防ぐ。
            initialSpawnSize = (cols, rows)
            initialSpawnTask?.cancel()
            initialSpawnTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.initialSpawnDebounce)
                guard !Task.isCancelled, let self, !self.didSpawn,
                      let size = self.initialSpawnSize else { return }
                await self.spawnIfNeeded(initialCols: size.cols, initialRows: size.rows)
            }
        } else if didSpawnComplete {
            try? await ptyManager.resize(id, cols: cols, rows: rows)
        } else {
            // spawn 中: PTY fd がまだ無効なため resize は失敗するので、
            // 最新 size を保持して spawnIfNeeded 完了時に反映する。
            pendingResize = (cols: cols, rows: rows)
        }
    }

    private var usesNonHookIdleFallback: Bool {
        if case .idleOnSpawnComplete = spawnRequest.statusBootstrap {
            true
        } else {
            false
        }
    }

    private func observeNonHookOutputIfNeeded(at outputAt: Date) {
        guard usesNonHookIdleFallback else { return }
        nonHookIdleFallbackTracker.observeOutputIfNeeded(
            at: outputAt,
            status: status,
            shouldSettle: { [weak self] in self?.status == .running },
            onSettled: { [weak self] in
                guard let self else { return }
            let timestamp = Date()
            let previousStatus = self.status
            self.transitionStatus(to: .idle, at: timestamp)
            // 非フック CLI は stop フックが来ないため、ここが turn 完了の確定点。
            // hook 経路（stop イベント処理）と同様に完了シーケンスを進めないと
            // waitUntilDone の完了条件（completedTurnSeq > baseline）が永遠に満たされない。
            // status == .running ガード済みのため awaitingApproval 中に進むことはない。
            self.completedTurnSeq += 1
            self.lastTurnCompletedAt = Date()
            self.notifyCompletionIfNeeded(from: previousStatus, to: self.status)
            }
        )
    }

    private func cancelNonHookIdleFallbackIfNeeded(for nextStatus: SessionStatus) {
        guard nextStatus != .running else { return }
        cancelNonHookIdleFallback()
    }

    private func cancelNonHookIdleFallback() {
        nonHookIdleFallbackTracker.cancel()
    }

    private func notifyCompletionIfNeeded(from previousStatus: SessionStatus, to nextStatus: SessionStatus) {
        guard previousStatus == .running, nextStatus == .idle else { return }
        // 本物のターン完了（running→idle）を未確認の停止としてラッチする。
        // escape 中断はこの経路を通らないため対象外（キャンセルは赤枠にしない）。
        hasUnseenCompletion = true
        SessionCompletionNotifier.notifyCompleted(sessionName: displayName)
        remoteSessionNotifier?.sessionCompleted(
            sessionId: id.description,
            sessionName: displayName
        )
    }

    private func transitionStatus(to newStatus: SessionStatus, at timestamp: Date) {
        guard status != newStatus else { return }
        status = newStatus
        eventSink?(id, newStatus, timestamp)
        // 承認待ち・完了・エラーへ入ったら「未確認の停止」をラッチする。
        // idle（ターン完了）は完了通知経路（notifyCompletionIfNeeded）で扱い、
        // escape 中断などの非完了 idle を赤枠から除外する。
        if newStatus.latchesUnseenAttentionOnEntry {
            hasUnseenCompletion = true
        }
    }
}

private extension Data {
    var containsSubmitKey: Bool {
        // 送信は CR(13) のみ。LF(10) は Shift+Enter による改行であり送信ではない。
        contains(13)
    }

    /// Escape キー単体。矢印 / ファンクションキー等の ESC(0x1b) 始まり複数バイト列は除外する。
    var isLoneEscape: Bool {
        count == 1 && first == 0x1b
    }
}

private extension SessionStatus {
    var isAwaitingApproval: Bool {
        if case .awaitingApproval = self {
            true
        } else {
            false
        }
    }

    var isReadyForInput: Bool {
        switch self {
        case .starting:
            false
        case .idle, .running, .awaitingApproval, .awaitingUserQuestion, .completed, .error:
            true
        }
    }
}

extension SessionViewModel: ControllableSession {
    public func sendText(_ text: String, submit: Bool) async throws {
        guard didSpawn else { throw ControllableSessionError.notSpawned }
        markAwaitingNewTurn()
        // 子アプリが bracketed paste mode を有効化しているときは本文をペーストとして
        // 包む。これにより codex のペーストバースト Enter 抑制窓(ADR 0002 §8)に末尾の
        // \r が巻き込まれず、長文でも確実に submit される。未対応 CLI(?2004h 未有効)では
        // 包まずに従来どおり送る(マーカー素通しによる表示崩れを防ぐ)。
        let wrapAsPaste = submit && terminalCoordinator.bracketedPasteMode
        if wrapAsPaste {
            try await ptyManager.write(Self.bracketedPasteStart, to: id)
        }
        try await ptyManager.write(Data(text.utf8), to: id)
        if wrapAsPaste {
            try await ptyManager.write(Self.bracketedPasteEnd, to: id)
        }
        if submit {
            submitBaselineTurnSeq = completedTurnSeq
            try await Task.sleep(for: submitKeyDelay)
            markInputSubmitted()
            try await ptyManager.write(Data("\r".utf8), to: id)
            // codex の submit 滞留(ADR 0002 §8.5)を次の再発で捕捉するための観測を始める。
            armSubmitDiagnostic(byteCount: Data(text.utf8).count, bracketed: wrapAsPaste)
        }
    }

    /// bracketed paste の開始/終了マーカー(CSI 200~ / CSI 201~)。SwiftTerm を直接 import
    /// しないよう DashboardFeature 層でバイト列を定義する(EscapeSequences と同値)。
    private static let bracketedPasteStart = Data([0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e])
    private static let bracketedPasteEnd = Data([0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e])

    public func readText(lines: Int) -> String {
        let text = terminalCoordinator.visibleText()
        guard lines > 0 else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(lines)
            .joined(separator: "\n")
    }

    public func consumeSubmitBaseline() {
        submitBaselineTurnSeq = nil
    }

    public func terminate() async {
        await kill()
    }
}
