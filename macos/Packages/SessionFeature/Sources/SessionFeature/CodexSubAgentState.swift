import Foundation
import CodexAppServerKit

enum CodexSubAgentPresentation {
    private static let displayIDPrefix = "codex-subagent:"

    static func displayID(for threadID: String) -> String {
        displayIDPrefix + threadID
    }

    static func threadID(from displayID: String) -> String? {
        guard displayID.hasPrefix(displayIDPrefix) else { return nil }
        return String(displayID.dropFirst(displayIDPrefix.count))
    }

    static func ref(for child: CodexChildThread) -> SubAgentRef {
        let summary = child.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SubAgentRef(
            id: displayID(for: child.id),
            subagentType: "Codex",
            description: summary.isEmpty || summary == child.id ? "Codex サブエージェント" : summary,
            status: status(for: child.status),
            startedAt: .distantPast
        )
    }

    /// 札の名前。親が spawn 時に付けたタスク名（agent_path 末尾）を最優先にする。
    /// 子の最初の usermessage は親の依頼文を引き継ぐことがあるので、タスク名が取れない（旧 spawn 方式）ときだけ使う。
    static func purpose(for thread: ThreadSummary) -> String? {
        if let name = taskName(for: thread.source) { return name }
        for turn in thread.turns ?? [] {
            for item in turn.items ?? [] where item.type?.lowercased() == "usermessage" {
                let text = item.text ?? item.raw?["content"]?.firstString(for: ["text"])
                if let title = usableTitle(text, threadID: thread.id) { return title }
            }
        }
        return usableTitle(thread.name, threadID: thread.id)
            ?? (thread.preview.contains(thread.id) ? nil : usableTitle(thread.preview, threadID: thread.id))
    }

    /// 一度得た親付けのタスク名は、後続の応答（thread/read など）が agent_path を省略しても失わない。
    static func keepingTaskName(_ new: CodexChildThread, from old: CodexChildThread?) -> CodexChildThread {
        guard new.taskName == nil, let name = old?.taskName else { return new }
        var kept = new
        kept.taskName = name
        kept.summary = name
        return kept
    }

    static func taskName(for source: ThreadSessionSource) -> String? {
        guard case .subAgent(let value) = source,
              let path = value["thread_spawn"]?["agent_path"]?.stringValue,
              let name = path.split(separator: "/").last,
              name != "root" else { return nil }
        return String(name).replacingOccurrences(of: "_", with: " ")
    }

    private static func usableTitle(_ text: String?, threadID: String) -> String? {
        guard let text else { return nil }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let title = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty || title == threadID || title.hasPrefix("subAgent:") ? nil : title
    }

    /// 失敗は明示された文字列だけ。refresh が status を省略した（unknown）・アンロードされた（notLoaded）など
    /// 「わからない」ものは完了側に倒す（完了済みの子を失敗として復活させない）。
    /// read 失敗（stale）は「確認できなかった」だけで、子の状態は書き換えない（最後に分かっていた状態を保つ）。
    static func status(for status: String) -> SubAgentStatus {
        switch status.lowercased() {
        case "active", "running", "inprogress", "in_progress": .running
        case "failed", "error", "systemerror": .failed
        case "interrupted": .stopped
        default: .completed
        }
    }

    /// 札の帯に出すのは実行中と失敗だけ。完了・停止（確認できた停止）は消え、✕ で閉じた札も出さない。
    static func isVisibleInStrip(_ ref: SubAgentRef, isDismissed: Bool) -> Bool {
        (ref.status == .running || ref.status == .failed) && !isDismissed
    }
}

public struct CodexChildThread: Identifiable, Equatable, Sendable {
    public let id: String
    public let parentThreadId: String
    public let ancestorThreadId: String?
    public let sourceIdentity: String?
    public var activeTurnId: String?
    public var status: String
    public var summary: String?
    /// 親が spawn 時に付けたタスク名（agent_path 末尾）。取れたら summary に優先して使い、後続応答で欠けても保つ。
    public var taskName: String?
    public let canAcceptDirectInput: Bool?

    public init(
        id: String,
        parentThreadId: String,
        ancestorThreadId: String? = nil,
        sourceIdentity: String? = nil,
        activeTurnId: String? = nil,
        status: String,
        summary: String? = nil,
        canAcceptDirectInput: Bool? = nil,
        taskName: String? = nil
    ) {
        self.id = id
        self.parentThreadId = parentThreadId
        self.ancestorThreadId = ancestorThreadId
        self.sourceIdentity = sourceIdentity
        self.activeTurnId = activeTurnId
        self.status = status
        self.summary = summary
        self.canAcceptDirectInput = canAcceptDirectInput
        self.taskName = taskName
    }
}

public struct CodexSubAgentStopRequest: Equatable, Sendable {
    public let threadId: String
    public let turnId: String
    public let parentThreadId: String

    public init(threadId: String, turnId: String, parentThreadId: String) {
        self.threadId = threadId
        self.turnId = turnId
        self.parentThreadId = parentThreadId
    }
}

public enum CodexSubAgentControlState: Equatable, Sendable {
    case available
    case unavailable
    case stale
}

public enum CodexSubAgentStopState: Equatable, Sendable {
    case available
    case stopping
    case stopped
    case unavailable
    case stale
}

public enum CodexSubAgentEvent: Equatable, Sendable {
    case available(children: [CodexChildThread])
    case validated(child: CodexChildThread)
    case stale(threadId: String, reason: String)
    case unavailable(reason: String)
    case turnCompleted(threadId: String, turnId: String, status: String)
}

public struct CodexSubAgentState: Equatable, Sendable {
    public let parentThreadId: String
    public private(set) var children: [CodexChildThread] = []

    private var controlStates: [String: CodexSubAgentControlState] = [:]
    private var stopStates: [String: CodexSubAgentStopState] = [:]
    private var pendingStops: [String: CodexSubAgentStopRequest] = [:]
    private var stopAttempts: [String: Int] = [:]
    private var unavailable = false
    private var staleIDs: Set<String> = []
    /// 失敗した / ユーザーが止めた子の「終わり方」。ひとつの規則で strip に残す:
    /// 残っている間は refresh・stale・notLoaded・unknown・idle で表示上の status も可視性も下げない。
    /// ユーザーの停止は完了通知の順序に頼らず、停止要求を出した時点で記録する。
    /// 外れるのは (1) 停止要求が失敗（rejectStop）、(2) 記録した turn と別の turn（activeTurnId が非 nil）で
    /// 実行中に戻った refresh、(3) `.unavailable`、(4) 一覧から消えたときだけ。turnId は記録した turn（不明なら nil）。
    private struct StickyTerminal: Equatable, Sendable {
        var status: String
        var turnId: String?
        var isUserStop = false
    }
    private var stickyTerminal: [String: StickyTerminal] = [:]
    /// 終わったと分かっている turn。終わった turn を「実行中」と言う古い refresh（in-flight）は無視する。
    /// refresh / stale は情報を落とす（lossy）ので、「turnId 付きで実行中」「実行中ではない」と言う以外の
    /// ことはさせない。終わり方（failed / interrupted）は turnCompleted・停止要求・明示された失敗だけが決める。
    private var endedTurns: [String: Set<String>] = [:]

    public init(parentThreadId: String) {
        self.parentThreadId = parentThreadId
    }

    public mutating func apply(_ event: CodexSubAgentEvent) {
        switch event {
        case .available(let incoming):
            unavailable = false
            let filtered = incoming.filter {
                $0.parentThreadId == parentThreadId
                    && ($0.ancestorThreadId == nil || $0.ancestorThreadId == parentThreadId)
            }
            let old = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0) })
            var latest: [String: CodexChildThread] = [:]
            var order: [String] = []
            for child in filtered {
                if latest[child.id] == nil { order.append(child.id) }
                latest[child.id] = child
            }
            var reconciled: [CodexChildThread] = []
            for id in order {
                if let child = latest[id] { reconciled.append(reconcile(CodexSubAgentPresentation.keepingTaskName(child, from: old[id]), previous: old[id])) }
            }
            children = reconciled
            let currentIDs = Set(children.map(\.id))
            staleIDs = staleIDs.intersection(currentIDs)
            stickyTerminal = stickyTerminal.filter { currentIDs.contains($0.key) }
            endedTurns = endedTurns.filter { currentIDs.contains($0.key) }
            pendingStops = pendingStops.filter { currentIDs.contains($0.key) }
            stopAttempts = stopAttempts.filter { currentIDs.contains($0.key) }
            for child in children {
                if let request = pendingStops[child.id], request.turnId != child.activeTurnId {
                    pendingStops.removeValue(forKey: child.id)
                }
            }
            for child in children { updateControlState(for: child) }
            for id in old.keys where !currentIDs.contains(id) {
                controlStates.removeValue(forKey: id)
                stopStates.removeValue(forKey: id)
            }
        case .validated(let child):
            guard child.parentThreadId == parentThreadId,
                  let index = children.firstIndex(where: { $0.id == child.id }) else { return }
            var validated = reconcile(CodexSubAgentPresentation.keepingTaskName(child, from: children[index]), previous: children[index])
            if validated.summary == nil { validated.summary = children[index].summary }
            children[index] = validated
            staleIDs.remove(child.id)
            updateControlState(for: validated)
        case .stale(let threadId, _):
            guard let index = children.firstIndex(where: { $0.id == threadId }) else { return }
            // 停止要求中は read 失敗で何も変えない（停止待ち・status・停止操作の状態を保つ）。
            // 停止の確認は interrupted の実報告だけで行い、確認が来なければ VM のタイムアウトが解除する。
            if pendingStops[threadId] != nil { return }
            staleIDs.insert(threadId)
            if let sticky = stickyTerminal[threadId] {
                // 失敗・停止済みの子は終わり方を見せる（stale は終わり方を書き換えない）。
                children[index].status = sticky.status
                children[index].activeTurnId = nil
                if let turn = sticky.turnId { endedTurns[threadId, default: []].insert(turn) }
            }
            // sticky でなければ status は触らない。読めなかっただけで、実行中の子を失敗にも完了にもしない
            // （失敗・完了になるのは Codex がそう報告したときだけ）。停止操作だけ下の stale で失効させる。
            controlStates[threadId] = .stale
            stopStates[threadId] = .stale
        case .unavailable:
            unavailable = true
            children.removeAll()
            pendingStops.removeAll()
            controlStates.removeAll()
            stopStates.removeAll()
            stopAttempts.removeAll()
            staleIDs.removeAll()
            stickyTerminal.removeAll()
            endedTurns.removeAll()
        case .turnCompleted(let threadId, let turnId, let status):
            guard let index = children.firstIndex(where: { $0.id == threadId }) else { return }
            let known = children[index].activeTurnId
            // 別の既知の turn を実行中なら、その turn の通知ではない。activeTurnId が消えている
            // （refresh が落とした）場合は、通知そのものを信頼して終わり方を記録する。
            if CodexSubAgentPresentation.status(for: children[index].status) == .running,
               let known, !turnId.isEmpty, known != turnId { return }
            let ended = turnId.isEmpty ? known : turnId
            // read 失敗（stale）は状態を書き換えないだけなので、その後に届いた実報告は通常どおり反映する。
            if status == "interrupted", let request = pendingStops[threadId], request.turnId == turnId {
                _ = acceptInterruptCompletion(request: request, threadId: threadId, turnId: turnId, status: status)
            } else {
                // 停止要求中に、interrupted ではない実報告（自然完了・失敗）が届いた。止まったのではないので、
                // 要求時に記録した「止めた」印は外し、届いた報告のとおりに扱う。
                if stickyTerminal[threadId]?.isUserStop == true, pendingStops[threadId] != nil {
                    stickyTerminal.removeValue(forKey: threadId)
                }
                if Self.isFailure(status) {
                    stickyTerminal[threadId] = StickyTerminal(status: status, turnId: ended)
                }
                // 記録済みの終わり方（失敗・ユーザー停止）は、後から来た通知で下げない。
                children[index].status = stickyTerminal[threadId]?.status ?? status
                children[index].activeTurnId = nil
                if let ended { endedTurns[threadId, default: []].insert(ended) }
                pendingStops.removeValue(forKey: threadId)
                controlStates[threadId] = .unavailable
                stopStates[threadId] = stickyTerminal[threadId]?.isUserStop == true ? .stopped : .unavailable
            }
        }
    }

    public func controlState(for threadId: String) -> CodexSubAgentControlState {
        controlStates[threadId] ?? (staleIDs.contains(threadId) ? .stale : .unavailable)
    }

    public func stopState(for threadId: String) -> CodexSubAgentStopState {
        stopStates[threadId] ?? (staleIDs.contains(threadId) ? .stale : .unavailable)
    }

    /// 失敗した / ユーザーが止めた子か（strip から勝手に外さない対象）。
    public func isSticky(_ threadId: String) -> Bool {
        stickyTerminal[threadId] != nil
    }

    public func canSendFollowUp(to threadId: String) -> Bool {
        false
    }

    public func stopAttempts(for threadId: String) -> Int {
        stopAttempts[threadId, default: 0]
    }

    public func stopAttemptCount(for threadId: String) -> Int {
        stopAttempts(for: threadId)
    }

    public mutating func stopRequest(for threadId: String) -> CodexSubAgentStopRequest? {
        guard !unavailable,
              let index = children.firstIndex(where: { $0.id == threadId }),
              !staleIDs.contains(threadId),
              let turnId = children[index].activeTurnId,
              !turnId.isEmpty,
              ["active", "running", "inProgress", "in_progress"].contains(children[index].status),
              pendingStops[threadId] == nil else { return nil }

        let request = CodexSubAgentStopRequest(
            threadId: threadId,
            turnId: turnId,
            parentThreadId: parentThreadId
        )
        pendingStops[threadId] = request
        // 停止は要求した時点で記録する（完了通知・refresh・stale の順序に依らず strip に残すため）。
        stickyTerminal[threadId] = StickyTerminal(status: "interrupted", turnId: turnId, isUserStop: true)
        stopAttempts[threadId, default: 0] += 1
        controlStates[threadId] = .available
        stopStates[threadId] = .stopping
        return request
    }

    public mutating func acceptInterruptCompletion(
        request: CodexSubAgentStopRequest,
        threadId: String,
        turnId: String,
        status: String
    ) -> Bool {
        guard status == "interrupted",
              request.parentThreadId == parentThreadId,
              request.threadId == threadId,
              request.turnId == turnId,
              pendingStops[threadId] == request,
              let index = children.firstIndex(where: { $0.id == threadId }),
              !staleIDs.contains(threadId) else { return false }

        children[index].status = status
        children[index].activeTurnId = nil
        pendingStops.removeValue(forKey: threadId)
        stopStates[threadId] = .stopped
        controlStates[threadId] = .unavailable
        stickyTerminal[threadId] = StickyTerminal(status: status, turnId: turnId, isUserStop: true)
        endedTurns[threadId, default: []].insert(turnId)
        return true
    }

    /// interrupt RPC が失敗したときだけ停止待ちを解除する。完了イベントの代用にはしない。
    public mutating func rejectStop(for threadId: String) {
        // 停止が起きなかったので止めた印を外し、通常の扱いに戻す。
        if stickyTerminal[threadId]?.isUserStop == true { stickyTerminal.removeValue(forKey: threadId) }
        guard pendingStops.removeValue(forKey: threadId) != nil,
              let child = children.first(where: { $0.id == threadId }) else { return }
        stopStates[threadId] = child.activeTurnId == nil ? .unavailable : .available
        controlStates[threadId] = child.activeTurnId == nil ? .unavailable : .available
    }

    /// 「実行中ではない」と言い切れる status。これ以外（省略・unknown・未知）は情報なしとして扱う。
    private static func isAuthoritativeNotRunning(_ status: String) -> Bool {
        ["notloaded", "idle", "completed", "interrupted", "cancelled", "canceled"].contains(status.lowercased())
    }

    private static func isFailure(_ status: String) -> Bool {
        ["error", "systemerror", "failed"].contains(status.lowercased())
    }

    /// refresh が届けた child 状態を、lossy な情報として不変条件に通す。
    /// 許すのは「turnId 付きで実行中」と「実行中ではない」だけ。終わり方は書かせず、既知の turnId を nil で消させず、
    /// 終わった turn の古い「実行中」で隠れた子を復活させない。明示された失敗は、子が終わったと分かっていないときだけ記録する。
    private mutating func reconcile(_ incoming: CodexChildThread, previous: CodexChildThread?) -> CodexChildThread {
        let id = incoming.id
        var result = incoming
        if Self.isFailure(incoming.status) {
            // 遅れて届いた refresh / read は turn を照合できないので、失敗を書けるのは子が終わったと分かっていないときだけ。
            // 完了して消えた札・止めた札・すでに失敗の札は、read で失敗に書き換えない。
            // 停止要求中の「止めた」印は、まだ終わったことを意味しない。失敗の実報告は反映し、停止待ちを解除する。
            if stickyTerminal[id]?.isUserStop == true, pendingStops[id] != nil {
                stickyTerminal.removeValue(forKey: id)
                pendingStops.removeValue(forKey: id)
            }
            if let previous, stickyTerminal[id] != nil || Self.isAuthoritativeNotRunning(previous.status) {
                return keeping(previous, over: incoming)
            }
            let turnId = incoming.activeTurnId ?? previous?.activeTurnId ?? stickyTerminal[id]?.turnId
            stickyTerminal[id] = StickyTerminal(status: incoming.status, turnId: turnId)
            if let turnId { endedTurns[id, default: []].insert(turnId) }
            result.activeTurnId = nil
            return result
        }
        let sticky = stickyTerminal[id]
        if CodexSubAgentPresentation.status(for: incoming.status) == .running {
            // turnId の無い「実行中」は断定できない。既知の状態を保つ（初見の子だけそのまま受ける）。
            guard let turn = incoming.activeTurnId, !turn.isEmpty else { return keeping(previous, over: incoming) }
            // 終わった turn の古い「実行中」（in-flight の遅延応答）は無視する。
            if endedTurns[id]?.contains(turn) == true { return keeping(previous, over: incoming) }
            if let sticky {
                if turn != sticky.turnId {
                    stickyTerminal.removeValue(forKey: id)   // 別の turn で実行中に戻った
                    return incoming
                }
                // 停止処理中（interrupt 待ち）の同じ turn は、そのまま停止中として見せる。
                if sticky.isUserStop, pendingStops[id] != nil { return incoming }
                return keeping(previous, over: incoming)
            }
            return incoming
        }
        // 省略・unknown・未知の status は「情報なし」。何も変えない（終わった turn としても記録しない）。
        guard Self.isAuthoritativeNotRunning(incoming.status) else { return keeping(previous, over: incoming) }
        // 実行中ではない。停止要求中に「完了」と報告されたなら、止まったのではなく自然完了。
        if sticky?.isUserStop == true, pendingStops[id] != nil, incoming.status.lowercased() == "completed" {
            stickyTerminal.removeValue(forKey: id)
            pendingStops.removeValue(forKey: id)
        } else if let sticky {
            result.status = sticky.status
            result.activeTurnId = nil
            if let turn = sticky.turnId { endedTurns[id, default: []].insert(turn) }
            // turn が終わったと分かったので interrupt 待ちは解く（停止済みは updateControlState が決める）。
            if sticky.isUserStop { pendingStops.removeValue(forKey: id) }
            return result
        }
        if let turn = previous?.activeTurnId { endedTurns[id, default: []].insert(turn) }
        result.activeTurnId = nil
        return result
    }

    /// 既知の状態（status / activeTurnId）を保ったまま、refresh の他の項目（summary など）だけ採る。
    private func keeping(_ previous: CodexChildThread?, over incoming: CodexChildThread) -> CodexChildThread {
        guard let previous else { return incoming }
        var kept = incoming
        kept.status = previous.status
        kept.activeTurnId = previous.activeTurnId
        return kept
    }

    private mutating func updateControlState(for child: CodexChildThread) {
        if staleIDs.contains(child.id) {
            controlStates[child.id] = .stale
            stopStates[child.id] = .stale
        } else if pendingStops[child.id] != nil {
            controlStates[child.id] = .available
            stopStates[child.id] = .stopping
        } else if stickyTerminal[child.id]?.isUserStop == true, child.activeTurnId == nil {
            controlStates[child.id] = .unavailable
            stopStates[child.id] = .stopped
        } else if child.activeTurnId == nil {
            controlStates[child.id] = .unavailable
            stopStates[child.id] = .unavailable
        } else {
            controlStates[child.id] = .available
            stopStates[child.id] = .available
        }
    }
}

public typealias CodexStopRequest = CodexSubAgentStopRequest
