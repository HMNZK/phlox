// 実パス（凍結時に PM が移す）:
// macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceSessionTitlePersistenceTests.swift
//
// task-44（UX-01b）受け入れテスト。名前四フィールドの保存・復元・PID 書き戻し・削除競合。
// 実バックエンドは起動しない。InMemorySessionStore と MockPTYManager / StructuredAgentClient のみ。
//
// 契約: tasks/task-44.md 保存・復元・rename / 復元完了時の PID 書き戻し / 成功基準 2。
// 期待値は契約リテラル。sleep の長さに依存せず、応答の解放と waitForPendingWrites() で順序を固定する。
// 実装役はアサーションを変更禁止。
// H5: 復元中の明示削除は復元終了後へ繰り越して反映する。要求時点では件数減少保存を抑止し、
// 最終ストアから消えることを期待する。

import Darwin
import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

private struct PersistenceSaveFailure: Error {}

private actor TitlePersistenceFailingStore: SessionStoreProtocol {
    private var stored: [PersistedSessionDescriptor]
    private(set) var saveAttempts = 0

    init(_ sessions: [PersistedSessionDescriptor] = []) {
        stored = sessions
    }

    func load() async -> [PersistedSessionDescriptor] {
        stored
    }

    func save(_ sessions: [PersistedSessionDescriptor]) async throws {
        saveAttempts += 1
        throw PersistenceSaveFailure()
    }

    func attemptCount() async -> Int { saveAttempts }
}

private actor TitlePersistenceRecordingStore: SessionStoreProtocol {
    private var stored: [PersistedSessionDescriptor]
    private(set) var saveSnapshots: [[SessionID]] = []

    init(_ sessions: [PersistedSessionDescriptor] = []) {
        stored = sessions
    }

    func load() async -> [PersistedSessionDescriptor] {
        stored
    }

    func save(_ sessions: [PersistedSessionDescriptor]) async throws {
        saveSnapshots.append(sessions.map(\.id))
        stored = sessions
    }
}

@MainActor
private final class RestorePIDGate {
    var holdIDs: Set<SessionID> = []
    var pids: [SessionID: pid_t] = [:]
    private var continuations: [SessionID: CheckedContinuation<pid_t?, Never>] = [:]
    private var waitingIDs: Set<SessionID> = []
    private var waitingWaiters: [SessionID: [CheckedContinuation<Void, Never>]] = [:]
    private var pendingRelease: Set<SessionID> = []
    private(set) var releasedIDs: Set<SessionID> = []

    func provide(_ id: SessionID) async -> pid_t? {
        if holdIDs.contains(id) {
            if pendingRelease.contains(id) {
                pendingRelease.remove(id)
                releasedIDs.insert(id)
                return pids[id]
            }
            waitingIDs.insert(id)
            waitingWaiters[id]?.forEach { $0.resume() }
            waitingWaiters[id] = nil
            return await withCheckedContinuation { continuation in
                continuations[id] = continuation
            }
        }
        return pids[id]
    }

    func waitUntilWaiting(_ id: SessionID) async {
        if waitingIDs.contains(id) { return }
        await withCheckedContinuation { continuation in
            waitingWaiters[id, default: []].append(continuation)
        }
    }

    var isWaiting: (SessionID) -> Bool {
        { [waitingIDs] id in waitingIDs.contains(id) }
    }

    func release(_ id: SessionID) {
        releasedIDs.insert(id)
        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(returning: pids[id])
        } else {
            pendingRelease.insert(id)
        }
    }
}

private actor TitleSpawnPIDGate {
    private var observedSessionID: SessionID?
    private var observationWaiters: [CheckedContinuation<SessionID, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func providePID(for sessionID: SessionID) async -> pid_t? {
        if let waiter = observationWaiters.first {
            observationWaiters.removeFirst()
            waiter.resume(returning: sessionID)
        } else {
            observedSessionID = sessionID
        }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        return 31
    }

    func nextObservedSessionID() async -> SessionID {
        if let observedSessionID {
            self.observedSessionID = nil
            return observedSessionID
        }
        return await withCheckedContinuation { continuation in
            observationWaiters.append(continuation)
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

private func expectState(
    _ state: SessionTitleState,
    _ name: String,
    _ source: SessionTitleSource,
    _ flowerName: String?,
    _ fullDerivedTitle: String?,
    _ label: String
) {
    #expect(state.name == name, Comment(rawValue: "\(label) name"))
    #expect(state.source == source, Comment(rawValue: "\(label) source"))
    #expect(state.flowerName == flowerName, Comment(rawValue: "\(label) flowerName"))
    #expect(state.fullDerivedTitle == fullDerivedTitle, Comment(rawValue: "\(label) fullDerivedTitle"))
}

private func titledDescriptor(
    id: SessionID,
    name: String,
    titleSource: SessionTitleSource?,
    flowerName: String?,
    fullDerivedTitle: String?,
    workingDirectory: String,
    backend: SessionBackend = .pty,
    pid: pid_t? = 1001,
    chatNativeSessionId: String? = nil,
    role: String? = nil
) -> PersistedSessionDescriptor {
    PersistedSessionDescriptor(
        id: id,
        kind: .claudeCode,
        workingDirectory: workingDirectory,
        name: name,
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        command: "/usr/local/bin/claude",
        args: [],
        env: [:],
        backend: backend,
        chatNativeSessionId: chatNativeSessionId,
        token: "token-\(id.rawValue.uuidString)",
        pid: pid,
        role: role,
        titleSource: titleSource,
        flowerName: flowerName,
        fullDerivedTitle: fullDerivedTitle
    )
}

@MainActor
private func waitForTitleCondition(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () async -> Bool
) async -> Bool {
    var elapsed: UInt64 = 0
    while await !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for title persistence condition")
            return false
        }
        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
    return true
}

@MainActor
private func capturingStandardError<R>(_ operation: () async throws -> R) async rethrows -> (R, String) {
    let pipe = Pipe()
    let original = dup(FileHandle.standardError.fileDescriptor)
    dup2(pipe.fileHandleForWriting.fileDescriptor, FileHandle.standardError.fileDescriptor)
    let result = try await operation()
    fflush(nil)
    pipe.fileHandleForWriting.closeFile()
    dup2(original, FileHandle.standardError.fileDescriptor)
    close(original)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (result, String(data: data, encoding: .utf8) ?? "")
}

private func fourTitleStates() -> [(String, SessionTitleSource?, String?, String?, String)] {
    [
        ("Rose", .flower, "Rose", nil, "flower"),
        ("ログイン画面を修正", .derived, "Rose", "ログイン画面を修正", "derived"),
        ("通知を修正", .manual, "Rose", nil, "manual"),
        ("", .manual, "Rose", nil, "empty"),
    ]
}

@Suite("task-44: session title persistence")
struct AcceptanceSessionTitlePersistenceTests {
    @Test @MainActor
    func 新規生成は花名状態で保存され_name_代入では手動化しない() async throws {
        let store = InMemorySessionStore()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store
            )
        )
        await dashboard.start()
        try await dashboard.spawnNewClaudeCodeSession()
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let node = try #require(dashboard.sessionNodes.first)
        let flowerBefore = node.titleState.flowerName
        #expect(node.titleState.source == .flower)
        #expect(node.titleState.flowerName == node.titleState.name)
        let saved = try #require(await store.load().first)
        expectState(
            saved.titleState,
            node.titleState.name,
            .flower,
            flowerBefore,
            nil,
            "spawn flower persist"
        )
    }

    @Test @MainActor
    func 初回保存前のPTY_renameは未保存を確認してから最新四フィールドを保存する() async throws {
        let store = InMemorySessionStore()
        let gate = TitleSpawnPIDGate()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store
            ),
            livePIDProvider: { id in await gate.providePID(for: id) }
        )
        await dashboard.start()
        let spawnTask = Task { @MainActor in
            try await dashboard.spawnNewClaudeCodeSession()
        }
        let id = await gate.nextObservedSessionID()
        #expect(await store.load().isEmpty, Comment(rawValue: "unsaved before first persist"))
        let flowerBefore = dashboard.sessionNode(id: id)?.titleState.flowerName
        dashboard.renameSession(id, to: "通知を修正")
        await gate.resume()
        _ = try await spawnTask.value
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let saved = try #require(await store.load().first)
        expectState(saved.titleState, "通知を修正", .manual, flowerBefore, nil, "first save latest pty")
        #expect(saved.pid == 31)
    }

    @Test @MainActor
    func 初回保存前のチャット導出は未保存を確認してから最新四フィールドを保存する() async throws {
        let store = InMemorySessionStore()
        let gate = TitleSpawnPIDGate()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store,
                appServerClientFactory: { _, _, _, _, _ in EventYieldingStructuredClient() }
            ),
            livePIDProvider: { id in await gate.providePID(for: id) }
        )
        await dashboard.start()
        let spawnTask = Task { @MainActor in
            try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
        }
        let id = await gate.nextObservedSessionID()
        #expect(await store.load().isEmpty, Comment(rawValue: "unsaved before chat persist"))
        let chat = try #require(dashboard.sessionNode(id: id)?.appServer)
        let flowerBefore = chat.titleState.flowerName
        try await chat.sendText("ログイン画面を修正", submit: true)
        await gate.resume()
        _ = try await spawnTask.value
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let saved = try #require(await store.load().first(where: { $0.id == id }))
        expectState(
            saved.titleState,
            "ログイン画面を修正",
            .derived,
            flowerBefore,
            "ログイン画面を修正",
            "first save derived chat"
        )
    }

    @Test @MainActor
    func 初回保存前の削除はdescriptorを再作成しない() async throws {
        let store = InMemorySessionStore()
        let gate = TitleSpawnPIDGate()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store
            ),
            livePIDProvider: { id in await gate.providePID(for: id) }
        )
        await dashboard.start()
        let spawnTask = Task { @MainActor in
            try await dashboard.spawnNewClaudeCodeSession()
        }
        let id = await gate.nextObservedSessionID()
        #expect(await store.load().isEmpty)
        _ = await dashboard.removeSession(id)
        await gate.resume()
        _ = try? await spawnTask.value
        await dashboard.waitForPendingPersistenceWritesForTesting()
        #expect(await store.load().contains(where: { $0.id == id }) == false)
        #expect(dashboard.sessionNode(id: id) == nil)
    }

    @Test @MainActor
    func 導出後の手動renameは保留書き込み完了後もmanualが勝つ() async throws {
        let store = InMemorySessionStore()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store,
                appServerClientFactory: { _, _, _, _, _ in EventYieldingStructuredClient() }
            )
        )
        await dashboard.start()
        let id = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
        let chat = try #require(dashboard.sessionNodes.first(where: { $0.id == id })?.appServer)
        let flowerBefore = chat.titleState.flowerName
        try await chat.sendText("ログイン画面を修正", submit: true)
        dashboard.renameSession(id, to: "通知を修正")
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let saved = try #require(await store.load().first(where: { $0.id == id }))
        expectState(saved.titleState, "通知を修正", .manual, flowerBefore, nil, "derive then manual")
        expectState(chat.titleState, "通知を修正", .manual, flowerBefore, nil, "vm after save")
    }

    @Test @MainActor
    func UIとCLIのrenameは同じ手動状態の一体更新へ到達する() async throws {
        let store = InMemorySessionStore()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store
            )
        )
        await dashboard.start()
        try await dashboard.spawnNewClaudeCodeSession()
        let id = dashboard.sessions[0].id
        let flowerBefore = dashboard.sessionNodes[0].titleState.flowerName
        dashboard.renameSession(id, to: " 通知を修正 \n")
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let saved = try #require(await store.load().first)
        expectState(saved.titleState, "通知を修正", .manual, flowerBefore, nil, "rename path")
    }

    @Test @MainActor
    func 空欄renameは空名のまま保存し復元後もshortIDを表示する() async throws {
        let store = InMemorySessionStore()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store
            )
        )
        await dashboard.start()
        try await dashboard.spawnNewClaudeCodeSession()
        let id = dashboard.sessions[0].id
        let flowerBefore = dashboard.sessionNodes[0].titleState.flowerName
        dashboard.renameSession(id, to: "   ")
        await dashboard.waitForPendingPersistenceWritesForTesting()
        #expect(await store.load().first?.name == "")
        let restored = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: AsyncStream<(SessionID, HookEvent)>.makeStream().0,
                sessions: store
            )
        )
        await restored.start()
        #expect(restored.sessions[0].name == "")
        #expect(restored.sessions[0].displayName == SessionViewModel.shortID(for: id))
        expectState(restored.sessionNodes[0].titleState, "", .manual, flowerBefore, nil, "empty restore")
    }

    @Test @MainActor
    func 花名重複回避はカタログ全件を予約すると接尾辞になりRoseを拾わない() async throws {
        let workspace = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspace) }
        let reserved = FlowerNameGenerator.names.enumerated().map { index, flower in
            titledDescriptor(
                id: SessionID(),
                name: "通知を修正-\(index)",
                titleSource: .manual,
                flowerName: flower,
                fullDerivedTitle: nil,
                workingDirectory: workspace.path
            )
        }
        let store = InMemorySessionStore(reserved)
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store,
                workspaceDirectory: workspace
            )
        )
        await dashboard.start()
        try await dashboard.spawnNewClaudeCodeSession()
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let reservedIDs = Set(reserved.map(\.id))
        let spawned = try #require(dashboard.sessionNodes.first(where: { !reservedIDs.contains($0.id) }))
        #expect(!FlowerNameGenerator.names.contains(spawned.titleState.name))
        #expect(spawned.titleState.flowerName.map(FlowerNameGenerator.names.contains) != true)
        #expect(spawned.titleState.name != "Rose")
        #expect(spawned.titleState.flowerName != "Rose")
    }

    @Test @MainActor
    func workspace移動は名前四フィールドを保持する() async throws {
        let workspace = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspace) }
        let moved = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(moved) }
        let id = SessionID()
        let store = InMemorySessionStore([
            titledDescriptor(
                id: id,
                name: "修正",
                titleSource: .derived,
                flowerName: "Rose",
                fullDerivedTitle: "修正",
                workingDirectory: workspace.path
            )
        ])
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store,
                workspaceDirectory: workspace
            )
        )
        await dashboard.start()
        await dashboard.changeWorkspace(id, to: moved)
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let saved = try #require(await store.load().first)
        expectState(saved.titleState, "修正", .derived, "Rose", "修正", "workspace move")
        #expect(saved.workingDirectory == moved.path)
    }

    @Test @MainActor
    func 初回保存失敗はlogErrorへ到達する() async throws {
        let store = TitlePersistenceFailingStore()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store
            )
        )
        let (_, stderr) = try await capturingStandardError {
            await dashboard.start()
            try await dashboard.spawnNewClaudeCodeSession()
            await dashboard.waitForPendingPersistenceWritesForTesting()
        }
        #expect(await store.attemptCount() > 0, Comment(rawValue: "first save attempted"))
        #expect(stderr.contains("Failed to persist"), Comment(rawValue: "first persist logError"))
        #expect(dashboard.sessionNodes[0].titleState.source == .flower)
    }

    @Test @MainActor
    func 既存セッションの名前保存失敗はlogErrorへ到達する() async throws {
        let workspace = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspace) }
        let id = SessionID()
        let store = TitlePersistenceFailingStore([
            titledDescriptor(
                id: id,
                name: "Rose",
                titleSource: .flower,
                flowerName: "Rose",
                fullDerivedTitle: nil,
                workingDirectory: workspace.path
            )
        ])
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                sessions: store,
                workspaceDirectory: workspace
            )
        )
        await dashboard.start()
        let flowerBefore = dashboard.sessionNode(id: id)?.titleState.flowerName
        let (_, stderr) = await capturingStandardError {
            dashboard.renameSession(id, to: "通知を修正")
            await dashboard.waitForPendingPersistenceWritesForTesting()
        }
        #expect(await store.attemptCount() > 0, Comment(rawValue: "name save attempted"))
        #expect(stderr.contains("Failed to persist session name"), Comment(rawValue: "name persist logError"))
        expectState(
            dashboard.sessionNodes[0].titleState,
            "通知を修正",
            .manual,
            flowerBefore,
            nil,
            "vm keeps title after name save failure"
        )
    }

    @Test @MainActor
    func PTY復元失敗プレースホルダはdescriptor経由の4状態を保持する() async throws {
        let workspace = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspace) }
        let descriptor = makeCustomAgentDescriptor()
        let catalog = AgentCatalog(customDescriptors: [descriptor])
        for (name, source, flower, full, label) in fourTitleStates() {
            let sessionID = SessionID()
            let store = InMemorySessionStore([
                PersistedSessionDescriptor(
                    id: sessionID,
                    agentRef: descriptor.ref,
                    workingDirectory: workspace.path,
                    name: name,
                    projectID: nil,
                    startedAt: Date(),
                    command: "/opt/homebrew/bin/aider",
                    args: ["--model", "sonnet"],
                    env: [:],
                    token: "token-\(sessionID.rawValue.uuidString)",
                    titleSource: source,
                    flowerName: flower,
                    fullDerivedTitle: full
                )
            ])
            let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
            let dashboard = DashboardViewModel(
                environment: makeTestEnvironment(
                    pty: MockPTYManager(),
                    hookStream: hookStream,
                    sessions: store,
                    workspaceDirectory: workspace,
                    customAgentBinaryPaths: [:],
                    agentCatalog: catalog
                )
            )
            await dashboard.start()
            let node = try #require(dashboard.sessionNode(id: sessionID))
            expectState(node.titleState, name, source ?? .manual, flower, full, "pty restore error \(label)")
        }
    }

    @Test @MainActor
    func チャット復元失敗プレースホルダはdescriptor経由の4状態を保持する() async throws {
        let workspace = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspace) }
        for (name, source, flower, full, label) in fourTitleStates() {
            let sessionID = SessionID()
            let store = InMemorySessionStore([
                titledDescriptor(
                    id: sessionID,
                    name: name,
                    titleSource: source,
                    flowerName: flower,
                    fullDerivedTitle: full,
                    workingDirectory: workspace.path,
                    backend: .appServer,
                    chatNativeSessionId: "thread-missing"
                )
            ])
            let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
            let dashboard = DashboardViewModel(
                environment: makeTestEnvironment(
                    pty: MockPTYManager(),
                    hookStream: hookStream,
                    sessions: store,
                    workspaceDirectory: workspace,
                    appServerClientFactory: { _, _, _, _, _ in
                        throw AgentSpawnError.unsupportedBackend
                    }
                )
            )
            await dashboard.start()
            let node = try #require(dashboard.sessionNode(id: sessionID))
            expectState(node.titleState, name, source ?? .manual, flower, full, "chat restore error \(label)")
        }
    }

    @Test @MainActor
    func PTY_PID書き戻しは最新手動名を残す() async throws {
        try await runPIDWritebackCase(
            backend: .pty,
            renameTo: "通知を修正",
            expected: ("通知を修正", .manual, "Rose", nil),
            deleteAfterRename: false
        )
    }

    @Test @MainActor
    func PTY_PID書き戻し_手動renameなし() async throws {
        try await runPIDWritebackCase(
            backend: .pty,
            renameTo: nil,
            expected: ("Rose", .flower, "Rose", nil),
            deleteAfterRename: false
        )
    }

    @Test @MainActor
    func PTY_PID書き戻し_空欄rename() async throws {
        try await runPIDWritebackCase(
            backend: .pty,
            renameTo: " \n",
            expected: ("", .manual, "Rose", nil),
            deleteAfterRename: false
        )
    }

    @Test @MainActor
    func PTY_PID書き戻し_削除後は再作成しない() async throws {
        try await runPIDWritebackCase(
            backend: .pty,
            renameTo: "通知を修正",
            expected: ("通知を修正", .manual, "Rose", nil),
            deleteAfterRename: true
        )
    }

    @Test @MainActor
    func チャット_PID書き戻しは最新手動名を残す() async throws {
        try await runPIDWritebackCase(
            backend: .appServer,
            renameTo: "通知を修正",
            expected: ("通知を修正", .manual, "Rose", nil),
            deleteAfterRename: false
        )
    }

    @Test @MainActor
    func チャット_PID書き戻し_手動renameなし() async throws {
        try await runPIDWritebackCase(
            backend: .appServer,
            renameTo: nil,
            expected: ("ログイン画面を修正", .derived, "Rose", "ログイン画面を修正"),
            deleteAfterRename: false
        )
    }

    @Test @MainActor
    func チャット_PID書き戻し_空欄rename() async throws {
        try await runPIDWritebackCase(
            backend: .appServer,
            renameTo: "",
            expected: ("", .manual, "Rose", nil),
            deleteAfterRename: false
        )
    }

    @Test @MainActor
    func チャット_PID書き戻し_削除後は再作成しない() async throws {
        try await runPIDWritebackCase(
            backend: .appServer,
            renameTo: "通知を修正",
            expected: ("通知を修正", .manual, "Rose", nil),
            deleteAfterRename: true
        )
    }
}

@MainActor
private func runPIDWritebackCase(
    backend: SessionBackend,
    renameTo: String?,
    expected: (String, SessionTitleSource, String?, String?),
    deleteAfterRename: Bool
) async throws {
    let workspace = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspace) }
    let idA = SessionID()
    let idB = SessionID()
    let initial = [
        titledDescriptor(
            id: idA,
            name: "Rose",
            titleSource: .flower,
            flowerName: "Rose",
            fullDerivedTitle: nil,
            workingDirectory: workspace.path,
            backend: backend,
            pid: 11,
            chatNativeSessionId: backend == .appServer ? "thread-a" : nil,
            role: "批判者"
        ),
        titledDescriptor(
            id: idB,
            name: "Lily",
            titleSource: .flower,
            flowerName: "Lily",
            fullDerivedTitle: nil,
            workingDirectory: workspace.path,
            backend: backend,
            pid: 12,
            chatNativeSessionId: backend == .appServer ? "thread-b" : nil
        ),
    ]
    let store = TitlePersistenceRecordingStore(initial)
    let gate = RestorePIDGate()
    gate.holdIDs = [idB]
    gate.pids = [idA: 21, idB: 22]
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    var environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        sessions: store,
        workspaceDirectory: workspace
    )
    if backend == .appServer {
        environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: store,
            workspaceDirectory: workspace,
            appServerClientFactory: { _, _, _, _, _ in EventYieldingStructuredClient() }
        )
    }
    let dashboard = DashboardViewModel(
        environment: environment,
        orphanReaper: MockOrphanReaper(alivePIDs: []),
        livePIDProvider: { id in await gate.provide(id) }
    )
    let startTask = Task { @MainActor in
        await dashboard.start()
    }
    defer {
        if !gate.releasedIDs.contains(idB) {
            gate.release(idB)
        }
    }
    let aVisible = await waitForTitleCondition { dashboard.sessionNode(id: idA) != nil }
    #expect(aVisible, Comment(rawValue: "A published"))
    let bWaiting = await waitForTitleCondition { gate.isWaiting(idB) }
    #expect(bWaiting, Comment(rawValue: "B PID gate reached"))
    #expect(gate.releasedIDs.contains(idB) == false, Comment(rawValue: "B not released yet"))

    dashboard.persistSessionRole(id: idA, role: "ファシリテーター")
    await dashboard.waitForPendingPersistenceWritesForTesting()

    if backend == .appServer, let chat = dashboard.sessionNode(id: idA)?.appServer {
        try await chat.sendText("ログイン画面を修正", submit: true)
        await dashboard.waitForPendingPersistenceWritesForTesting()
    }
    if let renameTo {
        dashboard.renameSession(idA, to: renameTo)
        await dashboard.waitForPendingPersistenceWritesForTesting()
    }
    if deleteAfterRename {
        _ = await dashboard.removeSession(idA)
        await dashboard.waitForPendingPersistenceWritesForTesting()
        #expect(
            await store.load().contains(where: { $0.id == idA }),
            Comment(rawValue: "delete requested during restore is deferred")
        )
    }
    gate.release(idB)
    #expect(gate.releasedIDs.contains(idB))
    await startTask.value
    await dashboard.waitForPendingPersistenceWritesForTesting()
    if deleteAfterRename {
        #expect(await store.load().contains(where: { $0.id == idA }) == false)
        #expect(dashboard.sessionNode(id: idA) == nil)
        return
    }
    let saved = try #require(await store.load().first(where: { $0.id == idA }))
    expectState(
        saved.titleState,
        expected.0,
        expected.1,
        expected.2,
        expected.3,
        "pid writeback \(backend)"
    )
    #expect(saved.pid == 21)
    #expect(saved.role == "ファシリテーター")
}
