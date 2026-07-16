import Foundation
import AgentDomain

/// アゴラ討論の発言者。ユーザーは特別参加者（発言数カウント外・配送対象）。
public enum AgoraSpeaker: Hashable, Sendable {
    case user
    case session(SessionID)
}

/// 追記専用討論ログの1エントリ。seq は単調増加・欠番なし（agmsg の共有ログモデルを参考）。
public struct AgoraLogEntry: Equatable, Sendable {
    public let seq: Int
    public let speaker: AgoraSpeaker
    public let text: String
    public let timestamp: Date

    public init(seq: Int, speaker: AgoraSpeaker, text: String, timestamp: Date) {
        self.seq = seq
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}

/// 発言順の制御方式。freeSpeech が v1 既定（decision-log 2026-07-11）。
public enum AgoraSchedulerKind: String, CaseIterable, Sendable {
    case freeSpeech
    case roundRobin
}

/// 討論の機械的制約一式。値は AgoraDiscussionSettings（task-6）が供給する。
public struct AgoraDiscussionConfig: Equatable, Sendable {
    /// PASS を除くエージェント実発言数の上限。到達で新規配送停止→最終まとめ→終了。
    public var maxUtterances: Int
    /// 参加エージェント数の上限。超過する招集要求は拒否する。
    public var maxAgents: Int
    /// 配送後にこの秒数 utteranceCompleted が無い参加者はスキップする。
    public var turnTimeoutSeconds: TimeInterval
    /// 他者の発言を挟まない同一参加者の連続発言上限。
    public var consecutiveSpeakLimit: Int
    /// 全参加者の PASS がこの周回続いたらファシリテーターへ停滞打開を促す。
    public var stallPassRounds: Int
    /// 残り発言数がこの値以下になったら配送 notice に残数警告を付す。
    public var warningRemaining: Int
    public var scheduler: AgoraSchedulerKind

    public init(
        maxUtterances: Int = 30,
        maxAgents: Int = 5,
        turnTimeoutSeconds: TimeInterval = 180,
        consecutiveSpeakLimit: Int = 2,
        stallPassRounds: Int = 2,
        warningRemaining: Int = 5,
        scheduler: AgoraSchedulerKind = .freeSpeech
    ) {
        self.maxUtterances = maxUtterances
        self.maxAgents = maxAgents
        self.turnTimeoutSeconds = turnTimeoutSeconds
        self.consecutiveSpeakLimit = consecutiveSpeakLimit
        self.stallPassRounds = stallPassRounds
        self.warningRemaining = warningRemaining
        self.scheduler = scheduler
    }
}

public enum AgoraEndReason: Equatable, Sendable {
    case utteranceLimitReached
    case stopped
}

public enum AgoraDiscussionPhase: Equatable, Sendable {
    case idle
    case discussing
    /// 上限到達後、ファシリテーターの最終まとめ待ち。
    case concluding
    case ended(AgoraEndReason)
}

/// 参加者ごとの討論状態。cursor＝配送済み seq（これより後が未読）。
public struct AgoraParticipantState: Equatable, Sendable {
    public let id: SessionID
    public var role: String?
    public var isFacilitator: Bool
    public var cursor: Int
    /// deliver 済みで utteranceCompleted 待ちの時刻。nil は待機なし（idle 扱い）。
    public var awaitingUtteranceSince: Date?
    public var consecutiveUtterances: Int
    public var consecutivePasses: Int

    public init(
        id: SessionID,
        role: String? = nil,
        isFacilitator: Bool = false,
        cursor: Int = 0,
        awaitingUtteranceSince: Date? = nil,
        consecutiveUtterances: Int = 0,
        consecutivePasses: Int = 0
    ) {
        self.id = id
        self.role = role
        self.isFacilitator = isFacilitator
        self.cursor = cursor
        self.awaitingUtteranceSince = awaitingUtteranceSince
        self.consecutiveUtterances = consecutiveUtterances
        self.consecutivePasses = consecutivePasses
    }
}

/// エンジンへの入力イベント。時刻は全て now 引数で受ける（エンジン内で Date() を呼ばない）。
public enum AgoraDiscussionEvent: Equatable, Sendable {
    case started(agenda: String, facilitatorID: SessionID, facilitatorRole: String?, now: Date)
    case participantJoined(id: SessionID, role: String?, now: Date)
    case summonRequested(role: String?, now: Date)
    case utteranceCompleted(id: SessionID, text: String, isPass: Bool, now: Date)
    case userUtterance(text: String, now: Date)
    case participantBecameIdle(id: SessionID, now: Date)
    case timeoutCheck(now: Date)
    case stopRequested(now: Date)
}

/// エンジンが返す副作用コマンド。実行（send/spawn/タイマー）は Coordinator（task-4）の責務。
public enum AgoraDiscussionCommand: Equatable, Sendable {
    /// entries を順に配送し、promptSpeak なら最後に発話を促す（実際の send 分割は Coordinator）。
    case deliver(to: SessionID, entries: [AgoraLogEntry], notice: String?, promptSpeak: Bool)
    case summon(role: String?)
    case rejectSummon(role: String?, reason: String)
    /// ファシリテーターへ最終まとめの発言を要求する（この応答の完了で end）。
    case requestConclusion(to: SessionID, notice: String)
    case end(AgoraEndReason)
}

/// アゴラ討論の純粋状態機械（task-1 契約・AcceptanceAgoraEngineTests が凍結）。
/// I/O・タイマー・SwiftUI 依存禁止。セマンティクスの正本は tasks/task-1.md。
public struct AgoraDiscussionEngine: Sendable {
    public private(set) var config: AgoraDiscussionConfig
    public private(set) var phase: AgoraDiscussionPhase
    public private(set) var log: [AgoraLogEntry]
    public private(set) var participants: [AgoraParticipantState]
    /// PASS を除くエージェント実発言数（ユーザー発言は数えない）。
    public private(set) var utteranceCount: Int
    public private(set) var agenda: String?
    private var roundRobinNextIndex: Int
    private var pendingStallNotice: Bool
    private var stallNoticeDispatchedForCurrentStall: Bool

    public init(config: AgoraDiscussionConfig) {
        self.config = config
        self.phase = .idle
        self.log = []
        self.participants = []
        self.utteranceCount = 0
        self.agenda = nil
        self.roundRobinNextIndex = 0
        self.pendingStallNotice = false
        self.stallNoticeDispatchedForCurrentStall = false
    }

    public mutating func apply(_ event: AgoraDiscussionEvent) -> [AgoraDiscussionCommand] {
        if case .ended = phase {
            return []
        }

        switch event {
        case .started(let agenda, let facilitatorID, let facilitatorRole, _):
            self.agenda = agenda
            phase = .discussing
            participants = [
                AgoraParticipantState(
                    id: facilitatorID,
                    role: facilitatorRole,
                    isFacilitator: true,
                    cursor: lastSeq
                )
            ]
            roundRobinNextIndex = participants.count > 1 ? 1 : 0
            pendingStallNotice = false
            stallNoticeDispatchedForCurrentStall = false
            return []

        case .participantJoined(let id, let role, _):
            guard !participants.contains(where: { $0.id == id }) else {
                return []
            }
            // 招集要求（summonRequested）と同じ上限を着地側でも強制する。
            // `spawn --role` の着地・手動追加はエンジン外で spawn が済んでいるため、
            // 超過分は登録しない（討論外の通常セッションとして残る）。
            guard participants.count < config.maxAgents else {
                return []
            }
            participants.append(AgoraParticipantState(id: id, role: role, cursor: lastSeq))
            normalizeRoundRobinIndex()
            return []

        case .summonRequested(let role, _):
            if participants.count < config.maxAgents {
                return [.summon(role: role)]
            }
            return [.rejectSummon(role: role, reason: "maximum agents reached")]

        case .utteranceCompleted(let id, let text, let isPass, let now):
            return handleUtteranceCompleted(id: id, text: text, isPass: isPass, now: now)

        case .userUtterance(let text, let now):
            return handleUserUtterance(text: text, now: now)

        case .participantBecameIdle(let id, let now):
            guard phase == .discussing, config.scheduler == .freeSpeech else {
                return []
            }
            return deliverUnreadIfPossible(to: id, now: now)

        case .timeoutCheck(let now):
            for index in participants.indices {
                guard let since = participants[index].awaitingUtteranceSince else {
                    continue
                }
                if now.timeIntervalSince(since) > config.turnTimeoutSeconds {
                    participants[index].awaitingUtteranceSince = nil
                }
            }
            return []

        case .stopRequested:
            phase = .ended(.stopped)
            return [.end(.stopped)]
        }
    }
}

private extension AgoraDiscussionEngine {
    var lastSeq: Int {
        log.last?.seq ?? 0
    }

    var facilitatorIndex: Int? {
        participants.firstIndex { $0.isFacilitator }
    }

    var capWarningNotice: String? {
        let remaining = config.maxUtterances - utteranceCount
        guard remaining <= config.warningRemaining else {
            return nil
        }
        return "残り発言数は \(max(remaining, 0)) です。"
    }

    var stallNotice: String {
        "討論が停滞しています。次の論点を提示してください。"
    }

    mutating func handleUtteranceCompleted(
        id: SessionID,
        text: String,
        isPass: Bool,
        now: Date
    ) -> [AgoraDiscussionCommand] {
        guard let participantIndex = participants.firstIndex(where: { $0.id == id }) else {
            return []
        }

        participants[participantIndex].awaitingUtteranceSince = nil

        if isPass {
            participants[participantIndex].consecutivePasses += 1
            guard phase == .discussing else {
                return []
            }
            return stallCommandsIfNeeded(now: now)
        }

        appendSessionUtterance(id: id, text: text, now: now)
        resetPasses()
        recordConsecutiveUtterance(for: id)

        if phase == .concluding {
            if participants[participantIndex].isFacilitator {
                phase = .ended(.utteranceLimitReached)
                return [.end(.utteranceLimitReached)]
            }
            return []
        }

        if utteranceCount >= config.maxUtterances {
            phase = .concluding
            guard let facilitatorIndex else {
                return []
            }
            participants[facilitatorIndex].awaitingUtteranceSince = now
            return [
                .requestConclusion(
                    to: participants[facilitatorIndex].id,
                    notice: "発言上限に達しました。討論をまとめてください。"
                )
            ]
        }

        guard config.scheduler == .roundRobin else {
            return []
        }
        return deliverNextRoundRobin(afterSpeaker: id, now: now)
    }

    mutating func handleUserUtterance(text: String, now: Date) -> [AgoraDiscussionCommand] {
        appendLog(speaker: .user, text: text, now: now)
        resetPasses()

        guard phase == .discussing, config.scheduler == .roundRobin else {
            return []
        }
        return deliverNextRoundRobin(afterSpeaker: nil, now: now)
    }

    mutating func appendSessionUtterance(id: SessionID, text: String, now: Date) {
        appendLog(speaker: .session(id), text: text, now: now)
        utteranceCount += 1
    }

    mutating func appendLog(speaker: AgoraSpeaker, text: String, now: Date) {
        log.append(
            AgoraLogEntry(
                seq: lastSeq + 1,
                speaker: speaker,
                text: text,
                timestamp: now
            )
        )
    }

    mutating func resetPasses() {
        for index in participants.indices {
            participants[index].consecutivePasses = 0
        }
        pendingStallNotice = false
        stallNoticeDispatchedForCurrentStall = false
    }

    mutating func recordConsecutiveUtterance(for id: SessionID) {
        for index in participants.indices {
            if participants[index].id == id {
                participants[index].consecutiveUtterances += 1
            } else {
                participants[index].consecutiveUtterances = 0
            }
        }
    }

    mutating func stallCommandsIfNeeded(now: Date) -> [AgoraDiscussionCommand] {
        let threshold = max(participants.count - 1, 0) * config.stallPassRounds
        guard threshold > 0 else {
            return []
        }
        let totalPasses = participants.reduce(0) { $0 + $1.consecutivePasses }
        guard totalPasses >= threshold, let facilitatorIndex else {
            return []
        }
        guard !stallNoticeDispatchedForCurrentStall, !pendingStallNotice else {
            return []
        }

        guard participants[facilitatorIndex].awaitingUtteranceSince == nil else {
            pendingStallNotice = true
            return []
        }

        guard let command = makeDeliver(
            toParticipantAt: facilitatorIndex,
            now: now,
            requiresUnread: false,
            includeStallNotice: true,
            promptSpeak: true
        ) else {
            return []
        }
        stallNoticeDispatchedForCurrentStall = true
        return [command]
    }

    mutating func deliverUnreadIfPossible(to id: SessionID, now: Date) -> [AgoraDiscussionCommand] {
        guard let participantIndex = participants.firstIndex(where: { $0.id == id }) else {
            return []
        }
        let shouldIncludePendingStall = participants[participantIndex].isFacilitator && pendingStallNotice
        // 停滞打開の nudge は独占防止（連続発言制限）に優先する（契約③。false だと討論が固まる）
        guard let command = makeDeliver(
            toParticipantAt: participantIndex,
            now: now,
            requiresUnread: !shouldIncludePendingStall,
            includeStallNotice: shouldIncludePendingStall,
            promptSpeak: shouldIncludePendingStall ? true : nil
        ) else {
            return []
        }

        if shouldIncludePendingStall {
            pendingStallNotice = false
            stallNoticeDispatchedForCurrentStall = true
        }
        return [command]
    }

    mutating func makeDeliver(
        toParticipantAt participantIndex: Int,
        now: Date,
        requiresUnread: Bool,
        includeStallNotice: Bool,
        promptSpeak: Bool?
    ) -> AgoraDiscussionCommand? {
        guard participants.indices.contains(participantIndex) else {
            return nil
        }
        guard participants[participantIndex].awaitingUtteranceSince == nil else {
            return nil
        }

        let targetID = participants[participantIndex].id
        let entries = unreadEntries(for: targetID)
        participants[participantIndex].cursor = lastSeq
        guard !requiresUnread || !entries.isEmpty else {
            return nil
        }

        participants[participantIndex].awaitingUtteranceSince = now
        return .deliver(
            to: targetID,
            entries: entries,
            notice: deliveryNotice(includeStallNotice: includeStallNotice),
            promptSpeak: promptSpeak ?? canPromptParticipant(at: participantIndex)
        )
    }

    func deliveryNotice(includeStallNotice: Bool) -> String? {
        var notices: [String] = []
        if includeStallNotice {
            notices.append(stallNotice)
        }
        if let capWarningNotice {
            notices.append(capWarningNotice)
        }
        guard !notices.isEmpty else {
            return nil
        }
        return notices.joined(separator: "\n")
    }

    func unreadEntries(for id: SessionID) -> [AgoraLogEntry] {
        guard let participant = participants.first(where: { $0.id == id }) else {
            return []
        }
        return log.filter { entry in
            guard entry.seq > participant.cursor else {
                return false
            }
            return entry.speaker != .session(id)
        }
    }

    func canPromptParticipant(at index: Int) -> Bool {
        participants[index].consecutiveUtterances < config.consecutiveSpeakLimit
    }

    mutating func deliverNextRoundRobin(afterSpeaker speakerID: SessionID?, now: Date) -> [AgoraDiscussionCommand] {
        guard !participants.isEmpty else {
            return []
        }

        let targetIndex: Int
        if let speakerID, let speakerIndex = participants.firstIndex(where: { $0.id == speakerID }) {
            targetIndex = (speakerIndex + 1) % participants.count
        } else {
            normalizeRoundRobinIndex()
            targetIndex = roundRobinNextIndex
        }

        roundRobinNextIndex = (targetIndex + 1) % participants.count
        guard let command = makeDeliver(
            toParticipantAt: targetIndex,
            now: now,
            requiresUnread: false,
            includeStallNotice: false,
            promptSpeak: nil
        ) else {
            return []
        }
        return [command]
    }

    mutating func normalizeRoundRobinIndex() {
        guard !participants.isEmpty else {
            roundRobinNextIndex = 0
            return
        }
        roundRobinNextIndex %= participants.count
    }
}
