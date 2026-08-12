import Foundation

public struct CodexChildThread: Identifiable, Equatable, Sendable {
    public let id: String
    public let parentThreadId: String
    public let ancestorThreadId: String?
    public var activeTurnId: String?
    public var status: String
    public var summary: String?
    public let canAcceptDirectInput: Bool?

    public init(
        id: String,
        parentThreadId: String,
        ancestorThreadId: String? = nil,
        activeTurnId: String? = nil,
        status: String,
        summary: String? = nil,
        canAcceptDirectInput: Bool? = nil
    ) {
        self.id = id
        self.parentThreadId = parentThreadId
        self.ancestorThreadId = ancestorThreadId
        self.activeTurnId = activeTurnId
        self.status = status
        self.summary = summary
        self.canAcceptDirectInput = canAcceptDirectInput
    }
}

public struct CodexSubAgentDetail: Equatable, Sendable {
    public let threadId: String
    public let transcript: [String]

    public init(threadId: String, transcript: [String]) {
        self.threadId = threadId
        self.transcript = transcript
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
    case detail(threadId: String, transcript: [String])
    case stale(threadId: String, reason: String)
    case unavailable(reason: String)
    case turnCompleted(threadId: String, turnId: String, status: String)
}

public struct CodexSubAgentState: Equatable, Sendable {
    public let parentThreadId: String
    public private(set) var children: [CodexChildThread] = []

    private var details: [String: CodexSubAgentDetail] = [:]
    private var controlStates: [String: CodexSubAgentControlState] = [:]
    private var stopStates: [String: CodexSubAgentStopState] = [:]
    private var pendingStops: [String: CodexSubAgentStopRequest] = [:]
    private var stopAttempts: [String: Int] = [:]
    private var unavailable = false
    private var staleIDs: Set<String> = []

    public init(parentThreadId: String) {
        self.parentThreadId = parentThreadId
    }

    public mutating func apply(_ event: CodexSubAgentEvent) {
        switch event {
        case .available(let incoming):
            unavailable = false
            let filtered = incoming.filter { $0.parentThreadId == parentThreadId }
            let old = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0) })
            var latest: [String: CodexChildThread] = [:]
            var order: [String] = []
            for child in filtered {
                if latest[child.id] == nil { order.append(child.id) }
                latest[child.id] = child
            }
            children = order.compactMap { latest[$0] }
            let currentIDs = Set(children.map(\.id))
            staleIDs = staleIDs.intersection(currentIDs)
            details = details.filter { currentIDs.contains($0.key) }
            pendingStops = pendingStops.filter { currentIDs.contains($0.key) }
            stopAttempts = stopAttempts.filter { currentIDs.contains($0.key) }
            for child in children {
                if let request = pendingStops[child.id], request.turnId != child.activeTurnId {
                    pendingStops.removeValue(forKey: child.id)
                }
            }
            for child in children {
                if staleIDs.contains(child.id) {
                    controlStates[child.id] = .stale
                    stopStates[child.id] = .stale
                } else if pendingStops[child.id] != nil {
                    controlStates[child.id] = .available
                    stopStates[child.id] = .stopping
                } else if stopStates[child.id] == .stopped, child.activeTurnId == nil {
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
            for id in old.keys where !currentIDs.contains(id) {
                controlStates.removeValue(forKey: id)
                stopStates.removeValue(forKey: id)
            }
        case .detail(let threadId, let transcript):
            guard children.contains(where: { $0.id == threadId }), !staleIDs.contains(threadId) else { return }
            details[threadId] = CodexSubAgentDetail(threadId: threadId, transcript: transcript)
        case .stale(let threadId, _):
            guard children.contains(where: { $0.id == threadId }) else { return }
            staleIDs.insert(threadId)
            pendingStops.removeValue(forKey: threadId)
            controlStates[threadId] = .stale
            stopStates[threadId] = .stale
            details.removeValue(forKey: threadId)
        case .unavailable:
            unavailable = true
            pendingStops.removeAll()
            for child in children {
                controlStates[child.id] = .unavailable
                stopStates[child.id] = .unavailable
            }
        case .turnCompleted(let threadId, let turnId, let status):
            guard let index = children.firstIndex(where: { $0.id == threadId }) else { return }
            guard !staleIDs.contains(threadId) else { return }
            guard children[index].activeTurnId == turnId else { return }
            if status == "interrupted", let request = pendingStops[threadId], request.turnId == turnId {
                _ = acceptInterruptCompletion(request: request, threadId: threadId, turnId: turnId, status: status)
            } else {
                children[index].status = status
                children[index].activeTurnId = nil
                pendingStops.removeValue(forKey: threadId)
                controlStates[threadId] = .unavailable
                stopStates[threadId] = .unavailable
            }
        }
    }

    public func detail(for threadId: String) -> CodexSubAgentDetail? {
        guard children.contains(where: { $0.id == threadId }), !staleIDs.contains(threadId) else { return nil }
        return details[threadId]
    }

    public func transcript(for threadId: String) -> [String] {
        detail(for: threadId)?.transcript ?? []
    }

    public func controlState(for threadId: String) -> CodexSubAgentControlState {
        controlStates[threadId] ?? (staleIDs.contains(threadId) ? .stale : .unavailable)
    }

    public func stopState(for threadId: String) -> CodexSubAgentStopState {
        stopStates[threadId] ?? (staleIDs.contains(threadId) ? .stale : .unavailable)
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
              !["completed", "interrupted", "failed", "error"].contains(children[index].status),
              pendingStops[threadId] == nil else { return nil }

        let request = CodexSubAgentStopRequest(
            threadId: threadId,
            turnId: turnId,
            parentThreadId: parentThreadId
        )
        pendingStops[threadId] = request
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
        return true
    }
}

public typealias CodexStopRequest = CodexSubAgentStopRequest
