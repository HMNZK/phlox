import Foundation
import AgentDomain
import SessionFeature

// 隠している秘密: PTY セッションの Codex ネイティブ resume ID を rollout 走査で発見・claim・永続化する詳細。

@MainActor
final class CodexNativeSessionDiscoveryController {
    private struct Context {
        let spawnTime: Date
        let workingDirectory: String
        let rolloutSnapshot: Set<String>
    }

    private let environment: AppEnvironment
    private let persistence: SessionPersistenceCoordinator
    private let retryInterval: Duration
    private let maxRetryDuration: Duration
    private let now: @Sendable () -> Date
    private let sessionsSnapshot: @MainActor () -> [SessionViewModel]
    private let sessionNodesSnapshot: @MainActor () -> [SessionNode]

    private var inFlightClaimedNativeIDs: Set<String> = []
    private var contexts: [SessionID: Context] = [:]
    private var tasks: [SessionID: Task<Void, Never>] = [:]

    init(
        environment: AppEnvironment,
        persistence: SessionPersistenceCoordinator,
        retryInterval: Duration,
        maxRetryDuration: Duration,
        now: @escaping @Sendable () -> Date,
        sessionsSnapshot: @escaping @MainActor () -> [SessionViewModel],
        sessionNodesSnapshot: @escaping @MainActor () -> [SessionNode]
    ) {
        self.environment = environment
        self.persistence = persistence
        self.retryInterval = retryInterval
        self.maxRetryDuration = maxRetryDuration
        self.now = now
        self.sessionsSnapshot = sessionsSnapshot
        self.sessionNodesSnapshot = sessionNodesSnapshot
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }

    var taskCount: Int {
        tasks.count
    }

    func persistCodexResumeIDIfNeeded(
        sessionID: SessionID,
        nativeSessionId: String?
    ) async {
        guard let nativeSessionId, !nativeSessionId.isEmpty else { return }
        guard let ref = sessionNodesSnapshot().first(where: { $0.id == sessionID })?.agentRef,
              let descriptor = environment.agentCatalog.descriptor(for: ref) else {
            return
        }

        if descriptor.launchSpec.followsNativeSessionIDFromHook {
            guard let normalizedNativeSessionId = Self.normalizedUUIDString(nativeSessionId) else { return }
            let catalog = environment.agentCatalog
            persistence.persistFollowedNativeResumeID(
                sessionID: sessionID,
                nativeSessionId: normalizedNativeSessionId,
                shouldFollow: { ref in
                    catalog.descriptor(for: ref)?.launchSpec.followsNativeSessionIDFromHook == true
                }
            )
            return
        }

        guard !persistence.hasPersistedCodexNativeResumeID(sessionID) else { return }
        guard descriptor.launchSpec.initialResumeIDStrategy == .codexNativeFromHook else {
            return
        }

        let catalog = environment.agentCatalog
        persistence.persistCodexNativeResumeID(
            sessionID: sessionID,
            nativeSessionId: nativeSessionId,
            isCodexNativeFromHook: { ref in
                catalog.descriptor(for: ref)?.launchSpec.initialResumeIDStrategy == .codexNativeFromHook
            }
        )
        if persistence.hasPersistedCodexNativeResumeID(sessionID) {
            finish(for: sessionID)
        }
    }

    func rolloutSnapshotIfNeeded(
        for ref: AgentRef,
        resumeID: String?,
        around spawnTime: Date
    ) -> Set<String>? {
        guard shouldDiscoverCodexNativeResumeID(for: ref, resumeID: resumeID) else { return nil }
        return makeDiscovery().snapshotExistingRollouts(around: spawnTime)
    }

    func configure(
        for session: SessionViewModel,
        spawnTime: Date,
        workingDirectory: String,
        rolloutSnapshot: Set<String>
    ) {
        let sessionID = session.id
        contexts[sessionID] = Context(
            spawnTime: spawnTime,
            workingDirectory: workingDirectory,
            rolloutSnapshot: rolloutSnapshot
        )
        session.onInputSubmitted = { [weak self] in
            self?.startIfNeeded(for: sessionID)
        }
        startIfNeeded(for: sessionID)
    }

    func finish(for sessionID: SessionID) {
        tasks.removeValue(forKey: sessionID)?.cancel()
        contexts.removeValue(forKey: sessionID)
        sessionNodesSnapshot().first(where: { $0.id == sessionID })?.pty?.onInputSubmitted = nil
    }

    func cancel(for sessionID: SessionID) {
        tasks.removeValue(forKey: sessionID)?.cancel()
        contexts.removeValue(forKey: sessionID)
        sessionNodesSnapshot().first(where: { $0.id == sessionID })?.pty?.onInputSubmitted = nil
    }

    private static func normalizedUUIDString(_ value: String) -> String? {
        guard let uuid = UUID(uuidString: value) else { return nil }
        return uuid.uuidString.lowercased()
    }

    private func shouldDiscoverCodexNativeResumeID(for ref: AgentRef, resumeID: String?) -> Bool {
        guard resumeID == nil else { return false }
        return environment.agentCatalog.descriptor(for: ref)?.launchSpec.initialResumeIDStrategy == .codexNativeFromHook
    }

    private func makeDiscovery() -> CodexSessionDiscovery {
        CodexSessionDiscovery(codexHome: environment.codexHome, now: now)
    }

    private func collectedClaimedNativeIDs() async -> Set<String> {
        var claimed = inFlightClaimedNativeIDs
        let persisted = await environment.sessions.load()
        for descriptor in persisted {
            if let resumeID = descriptor.resumeID {
                claimed.insert(resumeID.lowercased())
            }
        }
        return claimed
    }

    private func startIfNeeded(for sessionID: SessionID) {
        guard tasks[sessionID] == nil else { return }
        guard let context = contexts[sessionID] else { return }
        guard sessionsSnapshot().contains(where: { $0.id == sessionID }) else {
            cancel(for: sessionID)
            return
        }
        guard !persistence.hasPersistedCodexNativeResumeID(sessionID) else {
            finish(for: sessionID)
            return
        }

        tasks[sessionID] = Task { @MainActor [weak self] in
            defer { self?.tasks.removeValue(forKey: sessionID) }
            await self?.run(sessionID: sessionID, context: context)
        }
    }

    private func run(
        sessionID: SessionID,
        context: Context
    ) async {
        let discovery = makeDiscovery()
        let maxAttempts = max(
            1,
            Int(maxRetryDuration / retryInterval)
        )

        for attempt in 0..<maxAttempts {
            guard !Task.isCancelled else { return }
            guard sessionsSnapshot().contains(where: { $0.id == sessionID }) else { return }
            guard !persistence.hasPersistedCodexNativeResumeID(sessionID) else { return }

            let claimedIDs = await collectedClaimedNativeIDs()
            if let nativeID = discovery.discoverNativeSessionID(
                spawnTime: context.spawnTime,
                workingDirectory: context.workingDirectory,
                excluding: context.rolloutSnapshot,
                claimedIDs: claimedIDs
            ) {
                guard sessionsSnapshot().contains(where: { $0.id == sessionID }) else { return }
                guard !persistence.hasPersistedCodexNativeResumeID(sessionID) else { return }

                inFlightClaimedNativeIDs.insert(nativeID)
                await persistCodexResumeIDIfNeeded(sessionID: sessionID, nativeSessionId: nativeID)
                return
            }

            guard attempt + 1 < maxAttempts else { return }
            try? await Task.sleep(for: retryInterval)
        }
    }
}
