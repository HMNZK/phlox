import Foundation
import AgentDomain
import SessionFeature

// 隠している秘密: 復元ゲート中に永続 descriptor を再 plan・reap・再 spawn し、遅延 pid 書き戻しを行う詳細。

@MainActor
final class SessionRestoreCoordinator {
    private let environment: AppEnvironment
    private let persistence: SessionPersistenceCoordinator
    private let spawnService: SessionSpawnService
    private let codexDiscovery: CodexNativeSessionDiscoveryController
    private let orphanReaper: any OrphanReaper
    private let codexNow: @Sendable () -> Date
    private let livePIDProvider: @MainActor @Sendable (SessionID) async -> pid_t?
    private let appendPTYSession: @MainActor (SessionViewModel) -> Void
    private let appendAppServerSession: @MainActor (ChatSessionViewModel) -> Void
    private let refreshUnseenCompletionCount: @MainActor () -> Void
    private let publishRestoredSessionPresentation: @MainActor () -> Void
    private let logError: @MainActor (Error, String) -> Void

    /// 復元走査完了まで pid 書き戻しを遅延する（部分復元中の破壊的保存を避ける）。
    private var pendingRestorePIDUpdates: [PersistedSessionDescriptor] = []

    init(
        environment: AppEnvironment,
        persistence: SessionPersistenceCoordinator,
        spawnService: SessionSpawnService,
        codexDiscovery: CodexNativeSessionDiscoveryController,
        orphanReaper: any OrphanReaper,
        codexNow: @escaping @Sendable () -> Date,
        livePIDProvider: @escaping @MainActor @Sendable (SessionID) async -> pid_t?,
        appendPTYSession: @escaping @MainActor (SessionViewModel) -> Void,
        appendAppServerSession: @escaping @MainActor (ChatSessionViewModel) -> Void,
        refreshUnseenCompletionCount: @escaping @MainActor () -> Void,
        publishRestoredSessionPresentation: @escaping @MainActor () -> Void,
        logError: @escaping @MainActor (Error, String) -> Void
    ) {
        self.environment = environment
        self.persistence = persistence
        self.spawnService = spawnService
        self.codexDiscovery = codexDiscovery
        self.orphanReaper = orphanReaper
        self.codexNow = codexNow
        self.livePIDProvider = livePIDProvider
        self.appendPTYSession = appendPTYSession
        self.appendAppServerSession = appendAppServerSession
        self.refreshUnseenCompletionCount = refreshUnseenCompletionCount
        self.publishRestoredSessionPresentation = publishRestoredSessionPresentation
        self.logError = logError
    }

    func restorePersistedSessions() async {
        let persisted = await environment.sessions.load()
        guard !persisted.isEmpty else { return }

        persistence.beginSessionRestore()
        // defer で解除を保証する: 将来 restoreSession が throwing 化・early return 化しても
        // ゲートが張り付いたまま（=件数減少保存が永久に無効）にならないようにする。
        defer { persistence.completeSessionRestore() }
        pendingRestorePIDUpdates.removeAll(keepingCapacity: true)
        for descriptor in persisted {
            await restoreSession(descriptor)
        }
        persistence.completeSessionRestore()
        for descriptor in pendingRestorePIDUpdates {
            persistence.persistSession(descriptor)
        }
        pendingRestorePIDUpdates.removeAll(keepingCapacity: false)
        publishRestoredSessionPresentation()
    }

    /// 起動時 reconcile: descriptor に記録された前回プロセスの pid が生存していれば、
    /// その pid を pgid とするプロセスグループを reap してから（呼び出し元が）cold-restart 再 spawn する。
    /// 記録 pid が死亡／nil（旧 descriptor・捕捉失敗）のときは何もしない（従来挙動）。
    ///
    /// 不変条件: registry に記録された自分の pid 以外には一切シグナルを送らない
    /// （無関係プロセス・別アプリ不可侵）。reaper 経由でのみ判定・reap する。
    /// 前提: 二重起動（複数 Phlox 同時稼働）は未サポート＝スコープ外。pid 再利用の理論的
    /// リスクも既知制約として残す（本タスクでの対策は不要）。
    private func reconcileOrphan(for descriptor: PersistedSessionDescriptor) {
        guard let pid = descriptor.pid else { return }
        guard orphanReaper.isAlive(pid) else { return }
        orphanReaper.reap(pid)
    }

    private func restoreSession(_ descriptor: PersistedSessionDescriptor) async {
        let sessionID = descriptor.id
        let token = descriptor.token ?? SessionSpawnService.makeToken()

        // 前回プロセスの生存孤児（クラッシュ/強制終了の生き残り）を reap してから再 spawn する。
        // master fd を失った孤児は再アタッチ不能のため、reap → cold-restart 再 spawn が正しい。
        reconcileOrphan(for: descriptor)

        // 保存済みトークンを再登録することで ControlServer への認証を復元する。
        await environment.tokenStore.register(token, for: sessionID)

        if descriptor.backend == .appServer {
            await restoreChatSession(descriptor, token: token)
            return
        }

        do {
            let plan = try spawnService.prepareSessionLaunch(
                ref: descriptor.agentRef,
                sessionID: sessionID,
                sessionToken: token,
                workingDirectoryOverride: descriptor.workingDirectory,
                projectID: descriptor.projectID,
                launchMode: descriptor.resumeID.map { .resume(resumeID: $0) } ?? .newSession(),
                backend: .pty
            )
            let vm = spawnService.makeSessionViewModel(
                id: sessionID,
                startedAt: descriptor.startedAt,
                projectID: descriptor.projectID,
                parentSessionID: descriptor.parentSessionID,
                name: descriptor.name,
                plan: plan,
                launchContext: descriptor.launchContext
            )
            appendPTYSession(vm)
            await vm.start()

            let spawnTime = codexNow()
            let rolloutSnapshot = codexDiscovery.rolloutSnapshotIfNeeded(
                for: descriptor.agentRef,
                resumeID: descriptor.resumeID,
                around: spawnTime
            )
            await vm.spawnEager()
            if let rolloutSnapshot {
                codexDiscovery.configure(
                    for: vm,
                    spawnTime: spawnTime,
                    workingDirectory: descriptor.workingDirectory,
                    rolloutSnapshot: rolloutSnapshot
                )
            }

            // 再 spawn 後の新世代 live pid を descriptor へ書き戻す。復元走査完了後にまとめて永続化する。
            pendingRestorePIDUpdates.append(
                descriptor.updating(pid: await livePIDProvider(sessionID))
            )
        } catch {
            let vm = spawnService.makeRestoreErrorSession(
                descriptor,
                sessionToken: token,
                message: "restore failed: \(error)"
            )
            appendPTYSession(vm)
            await vm.start()
        }
    }

    private func restoreChatSession(_ descriptor: PersistedSessionDescriptor, token: String) async {
        do {
            let plan = try spawnService.prepareSessionLaunch(
                ref: descriptor.agentRef,
                sessionID: descriptor.id,
                sessionToken: token,
                workingDirectoryOverride: descriptor.workingDirectory,
                projectID: descriptor.projectID,
                launchMode: .newSession(),
                backend: .appServer
            )
            let vm = try await spawnService.makeChatSessionViewModel(
                id: descriptor.id,
                startedAt: descriptor.startedAt,
                projectID: descriptor.projectID,
                parentSessionID: descriptor.parentSessionID,
                name: descriptor.name,
                plan: plan,
                launchContext: descriptor.launchContext
            )
            appendAppServerSession(vm)
            guard let threadId = descriptor.chatNativeSessionId ?? descriptor.codexThreadId ?? descriptor.resumeID else {
                vm.markRestoreFailed("chat restore failed: missing thread id")
                refreshUnseenCompletionCount()
                return
            }
            await vm.restore(
                threadId: threadId,
                approvalPolicy: SessionSpawnService.appServerApprovalPolicy(for: descriptor.launchContext),
                sandbox: SessionSpawnService.appServerSandboxPolicy(for: descriptor.launchContext),
                persistedSettings: descriptor.codexSettings
            )
            refreshUnseenCompletionCount()

            // PTY 経路と同様、復元成功後の live pid は走査完了後にまとめて書き戻す。
            pendingRestorePIDUpdates.append(
                descriptor.updating(pid: await livePIDProvider(descriptor.id))
            )
        } catch {
            // A4: 復元準備・生成が throw しても silent drop しない。client 不在で安全に生成できる
            // プレースホルダ（イベントループ・接続を開始しない）を可視ノードとして載せ、失敗を UI に出す。
            // ここは復元走査ループから呼ばれるため、throw を外へ漏らさず他 descriptor の復元を継続させる。
            let placeholder = spawnService.makeRestoreErrorChatSession(
                descriptor,
                message: "chat restore failed: \(error)"
            )
            appendAppServerSession(placeholder)
            refreshUnseenCompletionCount()
            logError(error, "Failed to restore chat session \(descriptor.id)")
        }
    }
}
