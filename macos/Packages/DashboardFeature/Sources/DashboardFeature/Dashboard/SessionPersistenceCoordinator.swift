import Foundation
import AgentDomain
import MessageStore
import SessionFeature

private final class NotificationObserver: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

/// セッション/プロジェクト永続化の直列実行キュー（DashboardViewModel からの Extract Class、R2）。
///
/// すべての保存作業を単一チェーン（enqueue 順 = 書き込み順）で直列化し、
/// 古いスナップショットの後勝ち書き込みを防ぐ。load→mutate→save の
/// read-modify-write が重ならないことをこのチェーンが保証する。
@MainActor
final class SessionPersistenceCoordinator {
    private let sessionStore: any SessionStoreProtocol
    private let projectStore: any ProjectStoreProtocol
    private let logError: @MainActor @Sendable (Error, String) -> Void
    private var chain: Task<Void, Never> = Task {}
    /// codex native resumeID を保存済みのセッション（多重保存ガード）。
    private var persistedCodexNativeResumeIDs: Set<SessionID> = []
    private var persistedSessionIDs: Set<SessionID> = []
    private var latestChatNativeSessionIDs: [SessionID: String] = [:]
    private var chatNativeSessionObserver: NotificationObserver?
    /// 起動時セッション復元の走査完了前は、ストアのエントリ数を減らしうる保存を抑止する。
    private var isSessionRestoreInProgress = false

    init(
        sessionStore: any SessionStoreProtocol,
        projectStore: any ProjectStoreProtocol,
        logError: @escaping @MainActor @Sendable (Error, String) -> Void
    ) {
        self.sessionStore = sessionStore
        self.projectStore = projectStore
        self.logError = logError
        self.chatNativeSessionObserver = NotificationObserver(token: NotificationCenter.default.addObserver(
            forName: ChatNativeSessionIDNotification.name,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let sessionIDString = notification.userInfo?[ChatNativeSessionIDNotification.sessionIDKey] as? String,
                  let uuid = UUID(uuidString: sessionIDString),
                  let nativeSessionId = notification.userInfo?[ChatNativeSessionIDNotification.nativeSessionIDKey] as? String
            else { return }
            Task { @MainActor [weak self] in
                self?.persistChatNativeSessionID(
                    sessionID: SessionID(rawValue: uuid),
                    nativeSessionId: nativeSessionId
                )
            }
        })
    }

    /// 永続化作業を直列チェーンの末尾に連結する。書き込み順 = enqueue 順を保証する。
    func enqueue(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let previous = chain
        chain = Task { @MainActor in
            await previous.value
            await work()
        }
    }

    /// 起動時のセッション復元を開始する。全 descriptor の走査完了まで
    /// `completeSessionRestore()` を呼ぶまで、エントリ数を減らしうる保存を抑止する。
    func beginSessionRestore() {
        isSessionRestoreInProgress = true
    }

    /// セッション復元の走査完了を宣言し、通常の保存経路を再開する。
    func completeSessionRestore() {
        isSessionRestoreInProgress = false
    }

    /// 直列チェーン上の保留作業がすべて完了するまで待つ（テスト用。production の終了経路からは呼ばれない）。
    func waitForPendingWrites() async {
        await chain.value
    }

    /// descriptor を upsert する（同一 id の既存エントリは置き換え）。
    func persistSession(_ descriptor: PersistedSessionDescriptor) {
        persistedSessionIDs.insert(descriptor.id)
        enqueue {
            let descriptorToPersist: PersistedSessionDescriptor
            if descriptor.agentRef.builtinKind == .cursor,
               let nativeSessionId = self.latestChatNativeSessionIDs[descriptor.id] {
                descriptorToPersist = descriptor.updating(chatNativeSessionId: nativeSessionId)
            } else {
                if descriptor.agentRef.builtinKind != .cursor {
                    self.latestChatNativeSessionIDs.removeValue(forKey: descriptor.id)
                }
                descriptorToPersist = descriptor
            }
            var current = await self.sessionStore.load()
            let loadedCount = current.count
            current.removeAll { $0.id == descriptorToPersist.id }
            current.append(descriptorToPersist)
            try? await self.saveSessionsIfAllowed(loadedCount: loadedCount, updated: current)
        }
    }

    func removeSession(_ id: SessionID) {
        persistedSessionIDs.remove(id)
        latestChatNativeSessionIDs.removeValue(forKey: id)
        enqueue {
            var current = await self.sessionStore.load()
            let loadedCount = current.count
            current.removeAll { $0.id == id }
            try? await self.saveSessionsIfAllowed(loadedCount: loadedCount, updated: current)
        }
    }

    func persistSessionName(id: SessionID, name: String) {
        enqueue {
            var current = await self.sessionStore.load()
            guard let index = current.firstIndex(where: { $0.id == id }) else { return }
            let loadedCount = current.count
            current[index] = current[index].updating(name: name)
            do {
                try await self.saveSessionsIfAllowed(loadedCount: loadedCount, updated: current)
            } catch {
                self.logError(error, "Failed to persist session name for \(id)")
            }
        }
    }

    func persistSessionRole(id: SessionID, role: String) {
        enqueue {
            var current = await self.sessionStore.load()
            guard let index = current.firstIndex(where: { $0.id == id }) else { return }
            let loadedCount = current.count
            current[index] = current[index].updating(role: role)
            do {
                try await self.saveSessionsIfAllowed(loadedCount: loadedCount, updated: current)
            } catch {
                self.logError(error, "Failed to persist session role for \(id)")
            }
        }
    }

    /// 表示順を永続化する。順序は保存実行時点の `currentOrder()` を反映する
    /// （表示に無いエントリは既存の保存順を保って末尾に置く）。
    func persistSessionOrder(currentOrder: @escaping @MainActor @Sendable () -> [SessionID]) {
        enqueue {
            let sessionOrder = Dictionary(
                uniqueKeysWithValues: currentOrder().enumerated().map { ($0.element, $0.offset) }
            )
            let current = await self.sessionStore.load()
            let persistedOrder = Dictionary(
                uniqueKeysWithValues: current.enumerated().map { ($0.element.id, $0.offset) }
            )
            let sorted = current.sorted {
                let lhsOrder = sessionOrder[$0.id] ?? Int.max
                let rhsOrder = sessionOrder[$1.id] ?? Int.max
                if lhsOrder == rhsOrder {
                    return (persistedOrder[$0.id] ?? Int.max) < (persistedOrder[$1.id] ?? Int.max)
                }
                return lhsOrder < rhsOrder
            }
            do {
                try await self.saveSessionsIfAllowed(loadedCount: current.count, updated: sorted)
            } catch {
                self.logError(error, "Failed to persist session order")
            }
        }
    }

    /// changeWorkspace/moveSession 後の workingDirectory / projectID を descriptor へ反映する（B10）。
    /// PersistedSessionDescriptor に該当 updating ヘルパーが無いため全フィールドコピーで再構築する。
    func persistSessionWorkspace(id: SessionID, workingDirectory: String, projectID: ProjectID?) {
        enqueue {
            var current = await self.sessionStore.load()
            guard let index = current.firstIndex(where: { $0.id == id }) else { return }
            let existing = current[index]
            current[index] = PersistedSessionDescriptor(
                id: existing.id,
                agentRef: existing.agentRef,
                workingDirectory: workingDirectory,
                name: existing.name,
                projectID: projectID,
                startedAt: existing.startedAt,
                command: existing.command,
                args: existing.args,
                env: existing.env,
                backend: existing.backend,
                codexThreadId: existing.codexThreadId,
                chatNativeSessionId: existing.chatNativeSessionId,
                appServerUserAgent: existing.appServerUserAgent,
                codexSettings: existing.codexSettings,
                token: existing.token,
                resumeID: existing.resumeID,
                parentSessionID: existing.parentSessionID,
                pid: existing.pid,
                launchContext: existing.launchContext,
                role: existing.role
            )
            do {
                try await self.saveSessionsIfAllowed(loadedCount: current.count, updated: current)
            } catch {
                self.logError(error, "Failed to persist workspace change for \(id)")
            }
        }
    }

    func persistCodexSettings(id: SessionID, settings: CodexAppServerSessionSettings?) {
        enqueue {
            var current = await self.sessionStore.load()
            guard let index = current.firstIndex(where: { $0.id == id }) else { return }
            let loadedCount = current.count
            current[index] = current[index].updating(codexSettings: settings)
            do {
                try await self.saveSessionsIfAllowed(loadedCount: loadedCount, updated: current)
            } catch {
                self.logError(error, "Failed to persist Codex settings for \(id)")
            }
        }
    }

    /// structured chat backend の native session id を保存する。CLI resumeID とは別フィールドとして扱う。
    func persistChatNativeSessionID(sessionID: SessionID, nativeSessionId: String) {
        latestChatNativeSessionIDs[sessionID] = nativeSessionId
        guard persistedSessionIDs.contains(sessionID) else { return }
        enqueue {
            var current = await self.sessionStore.load()
            guard let index = current.firstIndex(where: { $0.id == sessionID }) else {
                self.persistedSessionIDs.remove(sessionID)
                return
            }
            let existing = current[index]
            guard existing.agentRef.builtinKind == .cursor else {
                self.latestChatNativeSessionIDs.removeValue(forKey: sessionID)
                return
            }
            guard existing.chatNativeSessionId != nativeSessionId else { return }

            current[index] = existing.updating(chatNativeSessionId: nativeSessionId)
            do {
                try await self.saveSessionsIfAllowed(loadedCount: current.count, updated: current)
            } catch {
                self.logError(error, "Failed to persist chat native session id for \(sessionID)")
            }
        }
    }

    /// codex native session id を resumeID として保存済みかどうか（enqueue 前の高速ガード用）。
    func hasPersistedCodexNativeResumeID(_ id: SessionID) -> Bool {
        persistedCodexNativeResumeIDs.contains(id)
    }

    /// codex native session id を resumeID として 1 度だけ保存する。
    /// 保存実行時点の descriptor が条件（codexNativeFromHook かつ resumeID 未設定）を満たすときだけ書き込む。
    func persistCodexNativeResumeID(
        sessionID: SessionID,
        nativeSessionId: String,
        isCodexNativeFromHook: @escaping @MainActor @Sendable (AgentRef) -> Bool
    ) {
        enqueue {
            var current = await self.sessionStore.load()
            guard let index = current.firstIndex(where: { $0.id == sessionID }) else { return }
            let existing = current[index]
            guard isCodexNativeFromHook(existing.agentRef), existing.resumeID == nil else { return }

            current[index] = existing.updating(resumeID: nativeSessionId)
            do {
                try await self.saveSessionsIfAllowed(loadedCount: current.count, updated: current)
                self.persistedCodexNativeResumeIDs.insert(sessionID)
            } catch {
                self.logError(error, "Failed to persist codex native session id for \(sessionID)")
            }
        }
    }

    /// フックが運ぶ native session id へ resumeID を on-change 追従する（claudeCode 専用経路）。
    func persistFollowedNativeResumeID(
        sessionID: SessionID,
        nativeSessionId: String,
        shouldFollow: @escaping @MainActor @Sendable (AgentRef) -> Bool
    ) {
        enqueue {
            var current = await self.sessionStore.load()
            guard let index = current.firstIndex(where: { $0.id == sessionID }) else { return }
            let existing = current[index]
            guard shouldFollow(existing.agentRef) else { return }
            guard existing.resumeID != nativeSessionId else { return }

            current[index] = existing.updating(resumeID: nativeSessionId)
            do {
                try await self.saveSessionsIfAllowed(loadedCount: current.count, updated: current)
            } catch {
                self.logError(error, "Failed to follow native session id for \(sessionID)")
            }
        }
    }

    /// プロジェクト一覧の呼び出し時点スナップショットを保存する（B5）。
    func persistProjects(_ snapshot: [Project]) {
        enqueue {
            let loaded = await self.projectStore.load()
            if self.isSessionRestoreInProgress, snapshot.count < loaded.count {
                return
            }
            do {
                try await self.projectStore.save(snapshot)
            } catch {
                self.logError(error, "Failed to persist projects")
            }
        }
    }

    private func saveSessionsIfAllowed(
        loadedCount: Int,
        updated: [PersistedSessionDescriptor]
    ) async throws {
        if isSessionRestoreInProgress, updated.count < loadedCount {
            return
        }
        try await sessionStore.save(updated)
    }
}
