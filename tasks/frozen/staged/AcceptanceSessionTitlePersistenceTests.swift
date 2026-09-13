// 実パス（凍結時に PM が移す）:
// macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceSessionTitlePersistenceTests.swift
//
// task-44（UX-01b）受け入れテスト。名前四フィールドの保存・復元・PID 書き戻し・削除競合。
// 実バックエンドは起動しない。InMemorySessionStore と MockPTYManager / StructuredAgentClient のみ。
//
// 契約: tasks/task-44.md 保存・復元・rename / 復元完了時の PID 書き戻し / 成功基準 2。
// 期待値は契約リテラル。sleep の長さに依存せず、応答の解放と waitForPendingWrites() で順序を固定する。
// 実装役はアサーションを変更禁止。

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

@MainActor
private final class RestorePIDGate {
    var holdIDs: Set<SessionID> = []
    var pids: [SessionID: pid_t] = [:]
    private var continuations: [SessionID: CheckedContinuation<pid_t?, Never>] = [:]

    func provide(_ id: SessionID) async -> pid_t? {
        if holdIDs.contains(id) {
            return await withCheckedContinuation { continuation in
                continuations[id] = continuation
            }
        }
        return pids[id]
    }

    func release(_ id: SessionID) {
        let pid = pids[id]
        continuations[id]?.resume(returning: pid)
        continuations.removeValue(forKey: id)
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
    chatNativeSessionId: String? = nil
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
        titleSource: titleSource,
        flowerName: flowerName,
        fullDerivedTitle: fullDerivedTitle
    )
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
        #expect(node.titleState.source == .flower)
        #expect(node.titleState.flowerName == node.titleState.name)
        let saved = try #require(await store.load().first)
        expectState(
            saved.titleState,
            node.titleState.name,
            .flower,
            node.titleState.flowerName,
            nil,
            "spawn flower persist"
        )
    }

    @Test @MainActor
    func 初回保存前のrenameは最新四フィールドを保存する() async throws {
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
        dashboard.renameSession(id, to: "通知を修正")
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let saved = try #require(await store.load().first)
        expectState(saved.titleState, "通知を修正", .manual, saved.titleState.flowerName, nil, "first save latest")
        #expect(saved.titleState.flowerName != nil)
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
        try await chat.sendText("ログイン画面を修正", submit: true)
        dashboard.renameSession(id, to: "通知を修正")
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let saved = try #require(await store.load().first(where: { $0.id == id }))
        expectState(saved.titleState, "通知を修正", .manual, saved.titleState.flowerName, nil, "derive then manual")
        expectState(chat.titleState, "通知を修正", .manual, chat.titleState.flowerName, nil, "vm after save")
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
        dashboard.renameSession(id, to: " 通知を修正 \n")
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let saved = try #require(await store.load().first)
        expectState(saved.titleState, "通知を修正", .manual, saved.titleState.flowerName, nil, "rename path")
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
        expectState(restored.sessionNodes[0].titleState, "", .manual, restored.sessionNodes[0].titleState.flowerName, nil, "empty restore")
    }

    @Test @MainActor
    func 花名重複回避は改名済みセッションのflowerNameも除外する() async throws {
        let workspace = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspace) }
        let existingID = SessionID()
        let store = InMemorySessionStore([
            titledDescriptor(
                id: existingID,
                name: "通知を修正",
                titleSource: .manual,
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
        try await dashboard.spawnNewClaudeCodeSession()
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let spawned = try #require(dashboard.sessionNodes.first(where: { $0.id != existingID }))
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
    func 保存失敗は初回保存を含め既存エラー記録へ到達する() async throws {
        let store = TitlePersistenceFailingStore()
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
        dashboard.renameSession(dashboard.sessions[0].id, to: "通知を修正")
        await dashboard.waitForPendingPersistenceWritesForTesting()
        #expect(await store.attemptCount() > 0, Comment(rawValue: "save attempted"))
        expectState(
            dashboard.sessionNodes[0].titleState,
            "通知を修正",
            .manual,
            dashboard.sessionNodes[0].titleState.flowerName,
            nil,
            "vm keeps title after save failure"
        )
    }

    @Test @MainActor
    func PTY復元失敗プレースホルダは名前状態を保持する() async throws {
        let workspace = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspace) }
        let descriptor = makeCustomAgentDescriptor()
        let catalog = AgentCatalog(customDescriptors: [descriptor])
        let sessionID = SessionID()
        let store = InMemorySessionStore([
            PersistedSessionDescriptor(
                id: sessionID,
                agentRef: descriptor.ref,
                workingDirectory: workspace.path,
                name: "Rose",
                projectID: nil,
                startedAt: Date(),
                command: "/opt/homebrew/bin/aider",
                args: ["--model", "sonnet"],
                env: [:],
                token: "token-\(sessionID.rawValue.uuidString)",
                titleSource: .flower,
                flowerName: "Rose",
                fullDerivedTitle: nil
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
        expectState(node.titleState, "Rose", .flower, "Rose", nil, "pty restore error")
    }

    @Test @MainActor
    func チャット復元失敗プレースホルダは名前状態を保持する() async throws {
        let workspace = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspace) }
        let sessionID = SessionID()
        let store = InMemorySessionStore([
            titledDescriptor(
                id: sessionID,
                name: "Rose",
                titleSource: .flower,
                flowerName: "Rose",
                fullDerivedTitle: nil,
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
        expectState(node.titleState, "Rose", .flower, "Rose", nil, "chat restore error")
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
    let store = InMemorySessionStore([
        titledDescriptor(
            id: idA,
            name: "Rose",
            titleSource: .flower,
            flowerName: "Rose",
            fullDerivedTitle: nil,
            workingDirectory: workspace.path,
            backend: backend,
            pid: 11,
            chatNativeSessionId: backend == .appServer ? "thread-a" : nil
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
    ])
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
    try await waitUntil { dashboard.sessionNode(id: idA) != nil }
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
    }
    gate.release(idB)
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
}
