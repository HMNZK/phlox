import Foundation
import AgentDomain
import SessionFeature

/// アゴラ討論の配線層（task-4 契約・AcceptanceAgoraCoordinatorTests が凍結）。
/// `AgoraDiscussionEngine`（純粋状態機械）のイベント供給とコマンド実行を担う。
/// 依存は全て `Effects` / snapshot 注入で差し替え可能（テストは実セッションなしで回る）。
/// セマンティクスの正本は tasks/task-4.md。公開 surface は暫定（PM 承認の上で調整可）。
@MainActor
public final class AgoraDiscussionCoordinator {
    /// 副作用の注入点。実配線は DashboardViewModel が組み立てる。
    public struct Effects {
        /// 発言リレー1件の送信。from=発言者（ユーザー由来は nil）。text は整形済み1行。
        /// submit は「発話促し」の最終メッセージのみ true。戻り値は配送成否。
        public var send: (_ from: SessionID?, _ to: SessionID, _ text: String, _ submit: Bool) async -> Bool
        /// 役割プロンプト等の複数行テキストをセッションへ直接注入する（ControllableSession.sendText 相当）。
        public var injectPrompt: (_ to: SessionID, _ prompt: String, _ submit: Bool) async -> Bool
        /// role 付きで claude チャットセッションを spawn する。成功で新セッション ID。
        public var summon: (_ role: String?) async -> SessionID?

        public init(
            send: @escaping (_ from: SessionID?, _ to: SessionID, _ text: String, _ submit: Bool) async -> Bool,
            injectPrompt: @escaping (_ to: SessionID, _ prompt: String, _ submit: Bool) async -> Bool,
            summon: @escaping (_ role: String?) async -> SessionID?
        ) {
            self.send = send
            self.injectPrompt = injectPrompt
            self.summon = summon
        }
    }

    /// tick ごとに観測する参加セッションの状態スナップショット。
    public struct ParticipantSnapshot {
        public let id: SessionID
        public let isIdle: Bool
        public let completedTurnSeq: Int
        public let transcript: [ChatItem]

        public init(id: SessionID, isIdle: Bool, completedTurnSeq: Int, transcript: [ChatItem]) {
            self.id = id
            self.isIdle = isIdle
            self.completedTurnSeq = completedTurnSeq
            self.transcript = transcript
        }
    }

    public private(set) var phase: AgoraDiscussionPhase = .idle
    public private(set) var utteranceCount: Int = 0
    public private(set) var maxUtterances: Int
    public private(set) var participants: [AgoraParticipantState] = []
    public private(set) var agenda: String?

    private let config: AgoraDiscussionConfig
    private let effects: Effects
    private var engine: AgoraDiscussionEngine
    private var observedCompletedTurnSeq: [SessionID: Int] = [:]
    private var transcriptBoundaryItemID: [SessionID: String] = [:]
    private var isDrainingOperations = false
    private var pendingOperations: [QueuedOperation] = []

    public init(config: AgoraDiscussionConfig, effects: Effects) {
        self.config = config
        self.effects = effects
        self.engine = AgoraDiscussionEngine(config: config)
        self.maxUtterances = config.maxUtterances
        publishEngineState()
    }

    /// 議題を投入して討論を開始する: ファシリテーターを summon し、役割プロンプト＋議題を注入する。
    public func start(agenda: String, now: Date) async {
        await enqueue { [weak self] in
            await self?.performStart(agenda: agenda, now: now)
        }
    }

    /// 参加者を討論へ登録する（ファシリテーターの `spawn --role` 着地と「＋」手動追加の合流点。
    /// 過去ログは配送しない。登録できた参加者には議題・発言規約の参加プロンプトを注入する
    /// （engine が上限超過で登録を拒否した場合は注入しない）。
    public func addParticipant(id: SessionID, role: String?, now: Date) async {
        // 登録の成立可否を await 復帰時点で観測できるよう、この操作だけは
        // 「自分の操作が処理されるまで」待つ（drain 進行中の早期復帰による
        // リネーム取りこぼしの根本対処・task-3 差し戻し1回目）。
        // 汎用 enqueue の「drain 中は即時復帰」は凍結済み coordinator 契約
        // （deliver 中の直列化テスト）の前提なので変えない。
        await enqueue(awaitCompletion: true) { [weak self] in
            guard let self else { return }
            await self.applyEvent(.participantJoined(id: id, role: role, now: now))
            self.observedCompletedTurnSeq[id] = self.observedCompletedTurnSeq[id] ?? 0
            guard self.engine.participants.contains(where: { $0.id == id }),
                  let agenda = self.engine.agenda else { return }
            let prompt = AgoraRolePromptTemplate.prompt(
                role: role,
                agenda: agenda,
                isFacilitator: false,
                config: self.config
            )
            _ = await self.effects.injectPrompt(id, prompt, true)
        }
    }

    /// ユーザーの composer 発言を討論へ合流させる（全参加者へ配送対象・発言数には数えない）。
    public func submitUserUtterance(_ text: String, now: Date) async {
        await enqueue { [weak self] in
            guard let self, !self.isEnded else { return }
            let sanitized = AgoraUtteranceExtraction.sanitizedLine(text)
            guard !sanitized.isEmpty else { return }
            await self.applyEvent(.userUtterance(text: sanitized, now: now))
        }
    }

    /// 討論を打ち切る（以後の観測・配送を停止する）。
    public func stop(now: Date) async {
        await enqueue { [weak self] in
            await self?.applyEvent(.stopRequested(now: now))
        }
    }

    /// 観測ループの1刻み。既存の 350ms tick から呼ばれ、turn 完了検知・idle 配送・
    /// タイムアウトをエンジンへ供給し、返ったコマンドを直列に実行する。
    public func tick(now: Date, snapshots: [ParticipantSnapshot]) async {
        await enqueue { [weak self] in
            await self?.performTick(now: now, snapshots: snapshots)
        }
    }
}

private extension AgoraDiscussionCoordinator {
    struct QueuedOperation {
        let run: () async -> Void
        let completion: CheckedContinuation<Void, Never>?
    }

    var isEnded: Bool {
        if case .ended = phase { return true }
        return false
    }

    /// 不変条件: `awaitCompletion: true` を drain 中の operation 内（Effects クロージャ等）から
    /// 呼んではならない。drain は operation の完了を直列に待つため自己デッドロックする。
    func enqueue(
        awaitCompletion: Bool = false,
        _ operation: @escaping () async -> Void
    ) async {
        await withCheckedContinuation { continuation in
            if isDrainingOperations {
                if awaitCompletion {
                    // 呼び出し元が「操作の処理完了」を待つ（addParticipant 専用）。
                    pendingOperations.append(QueuedOperation(run: operation, completion: continuation))
                } else {
                    // 従来契約: drain 進行中の enqueue は積むだけで即時復帰する。
                    pendingOperations.append(QueuedOperation(run: operation, completion: nil))
                    continuation.resume()
                }
                return
            }

            pendingOperations.append(QueuedOperation(run: operation, completion: continuation))
            isDrainingOperations = true
            Task { @MainActor [weak self] in
                await self?.drainOperations()
            }
        }
    }

    func drainOperations() async {
        while !pendingOperations.isEmpty {
            let operation = pendingOperations.removeFirst()
            await operation.run()
            publishEngineState()
            operation.completion?.resume()
        }
        isDrainingOperations = false
    }

    func performStart(agenda: String, now: Date) async {
        guard phase == .idle else { return }
        let facilitatorRole = "ファシリテーター"
        guard let facilitatorID = await effects.summon(facilitatorRole) else { return }
        await applyEvent(.started(
            agenda: agenda,
            facilitatorID: facilitatorID,
            facilitatorRole: facilitatorRole,
            now: now
        ))
        observedCompletedTurnSeq[facilitatorID] = 0
        let prompt = AgoraRolePromptTemplate.prompt(
            role: facilitatorRole,
            agenda: agenda,
            isFacilitator: true,
            config: config
        )
        _ = await effects.injectPrompt(facilitatorID, prompt, true)
    }

    func performTick(now: Date, snapshots: [ParticipantSnapshot]) async {
        guard !isEnded else { return }
        let participantIDs = Set(participants.map(\.id))
        let participantSnapshots = snapshots.filter { participantIDs.contains($0.id) }

        for snapshot in participantSnapshots where !isEnded && snapshot.isIdle {
            await applyEvent(.participantBecameIdle(id: snapshot.id, now: now))
        }

        for snapshot in participantSnapshots where !isEnded {
            await observeCompletedTurn(snapshot, now: now)
        }

        if !isEnded {
            await applyEvent(.timeoutCheck(now: now))
        }
    }

    func observeCompletedTurn(_ snapshot: ParticipantSnapshot, now: Date) async {
        let lastObservedSeq = observedCompletedTurnSeq[snapshot.id] ?? 0
        guard snapshot.completedTurnSeq > lastObservedSeq else { return }

        let boundary = transcriptBoundaryItemID[snapshot.id]
        // transcript 置換（revert/rebuild）検知: 保持中の境界 itemID が「非 nil なのに現 transcript に不在」なら
        // transcript が丸ごと置換されたとみなす。AgoraUtteranceExtraction は afterItemID 未発見時に全件へ
        // フォールバックするため、そのまま抽出すると過去発言が1発言として再計上・巨大二重配送される。
        // これを防ぐため抽出せず境界を現末尾へリセットし、当該 turn をスキップする（安全側）。
        // 境界 nil（初回・過去ログ非配送の仕様）は従来どおりフォールバック抽出に委ねる（凍結挙動を維持）。
        if let boundary, !snapshot.transcript.contains(where: { $0.id == boundary }) {
            observedCompletedTurnSeq[snapshot.id] = snapshot.completedTurnSeq
            transcriptBoundaryItemID[snapshot.id] = snapshot.transcript.last?.id
            return
        }

        guard let utterance = AgoraUtteranceExtraction.utterance(
            transcript: snapshot.transcript,
            afterItemID: boundary
        ) else {
            return
        }

        observedCompletedTurnSeq[snapshot.id] = snapshot.completedTurnSeq
        if let lastID = snapshot.transcript.last?.id {
            transcriptBoundaryItemID[snapshot.id] = lastID
        }

        let sanitized = AgoraUtteranceExtraction.sanitizedLine(utterance)
        let isPass = AgoraUtteranceExtraction.isPass(utterance)
        await applyEvent(.utteranceCompleted(
            id: snapshot.id,
            text: sanitized,
            isPass: isPass,
            now: now
        ))
    }

    func applyEvent(_ event: AgoraDiscussionEvent) async {
        guard !isEnded || event == .stopRequested(now: eventNow(event)) else { return }
        let commands = engine.apply(event)
        publishEngineState()
        await execute(commands)
        publishEngineState()
    }

    func execute(_ commands: [AgoraDiscussionCommand]) async {
        for command in commands {
            guard !isEnded || isEndCommand(command) else { return }
            switch command {
            case .deliver(let to, let entries, let notice, let promptSpeak):
                await executeDeliver(to: to, entries: entries, notice: notice, promptSpeak: promptSpeak)
            case .summon(let role):
                await executeSummon(role: role)
            case .rejectSummon:
                break
            case .requestConclusion(let to, let notice):
                let text = AgoraUtteranceExtraction.sanitizedLine(notice)
                guard !text.isEmpty else { break }
                _ = await effects.send(nil, to, text, true)
            case .end:
                publishEngineState()
                return
            }
        }
    }

    func executeDeliver(
        to: SessionID,
        entries: [AgoraLogEntry],
        notice: String?,
        promptSpeak: Bool
    ) async {
        for entry in entries {
            guard !isEnded else { return }
            let text = AgoraUtteranceExtraction.sanitizedLine(entry.text)
            guard !text.isEmpty else { continue }
            _ = await effects.send(entry.speaker.sessionID, to, text, false)
        }

        let prompt = deliveryPrompt(notice: notice, promptSpeak: promptSpeak)
        guard !prompt.isEmpty, !isEnded else { return }
        _ = await effects.send(nil, to, prompt, promptSpeak)
    }

    func executeSummon(role: String?) async {
        guard let newID = await effects.summon(role), let agenda = engine.agenda else { return }
        await applyEvent(.participantJoined(id: newID, role: role, now: Date()))
        observedCompletedTurnSeq[newID] = 0
        let prompt = AgoraRolePromptTemplate.prompt(
            role: role,
            agenda: agenda,
            isFacilitator: false,
            config: config
        )
        _ = await effects.injectPrompt(newID, prompt, true)
    }

    func deliveryPrompt(notice: String?, promptSpeak: Bool) -> String {
        var parts: [String] = []
        if let notice, !notice.isEmpty {
            parts.append(notice)
        }
        if promptSpeak {
            parts.append("発言してください。発言不要なときは PASS とだけ返してください。")
        }
        return AgoraUtteranceExtraction.sanitizedLine(parts.joined(separator: "\n"))
    }

    func publishEngineState() {
        phase = engine.phase
        utteranceCount = engine.utteranceCount
        maxUtterances = engine.config.maxUtterances
        participants = engine.participants
        agenda = engine.agenda
    }

    func isEndCommand(_ command: AgoraDiscussionCommand) -> Bool {
        if case .end = command { return true }
        return false
    }

    func eventNow(_ event: AgoraDiscussionEvent) -> Date {
        switch event {
        case .started(_, _, _, let now),
             .participantJoined(_, _, let now),
             .summonRequested(_, let now),
             .utteranceCompleted(_, _, _, let now),
             .userUtterance(_, let now),
             .participantBecameIdle(_, let now),
             .timeoutCheck(let now),
             .stopRequested(let now):
            return now
        }
    }
}

private extension AgoraSpeaker {
    var sessionID: SessionID? {
        if case .session(let id) = self { return id }
        return nil
    }
}
