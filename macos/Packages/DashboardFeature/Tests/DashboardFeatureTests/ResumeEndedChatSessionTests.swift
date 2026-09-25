import Foundation
import Testing
import AgentDomain
import HookServer
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// 04 B3「この会話から再開」: プロセスが終わったチャットを、同じ会話 ID で新しいプロセスに差し替える。
@Test @MainActor
func resumeEndedChatSession_replacesTheNodeInPlaceAndResumesTheSameConversation() async throws {
    let sessionStore = InMemorySessionStore()
    let spawnClient = CountingResumeStructuredClient()
    let resumeClient = CountingResumeStructuredClient()
    let clients = StructuredClientSequence([spawnClient, resumeClient])
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        sessions: sessionStore,
        agentBinaryPaths: [.claudeCode: "/bin/echo"],
        appServerClientFactory: { _, _, _, _, _ in try clients.next() }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let other = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .pty)
    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    let resumeID = sessionID.rawValue.uuidString.lowercased()
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == resumeID
    }
    guard case .appServer(let ended) = try #require(dashboard.sessionNode(id: sessionID)) else {
        Issue.record("chat node expected")
        return
    }
    // 終わる前は再開の対象にならない。
    await dashboard.resumeEndedChatSession(sessionID)
    #expect(resumeClient.resumes.isEmpty)

    spawnClient.yield(.processExited(exitCode: 1))
    try await waitUntil { ended.processExit != nil }
    #expect(ended.resumeConversationHandler != nil)

    await dashboard.resumeEndedChatSession(sessionID)

    #expect(resumeClient.resumes == [resumeID])
    guard case .appServer(let resumed) = try #require(dashboard.sessionNode(id: sessionID)) else {
        Issue.record("chat node expected")
        return
    }
    #expect(resumed !== ended)
    #expect(resumed.processExit == nil)
    #expect(resumed.resumeConversationHandler != nil)
    #expect(dashboard.sessionNodes.map(\.id) == [other, sessionID])
}

// 続けて押しても、2 つ目のプロセスは作らない。
@Test @MainActor
func resumeEndedChatSession_ignoresASecondPressWhileResuming() async throws {
    let sessionStore = InMemorySessionStore()
    let spawnClient = CountingResumeStructuredClient()
    let resumeClient = CountingResumeStructuredClient()
    let clients = StructuredClientSequence([spawnClient, resumeClient])
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        sessions: sessionStore,
        agentBinaryPaths: [.claudeCode: "/bin/echo"],
        appServerClientFactory: { _, _, _, _, _ in try clients.next() }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    try await waitUntil { await sessionStore.load().contains { $0.id == sessionID } }
    guard case .appServer(let ended) = try #require(dashboard.sessionNode(id: sessionID)) else {
        Issue.record("chat node expected")
        return
    }
    spawnClient.yield(.processExited(exitCode: 1))
    try await waitUntil { ended.processExit != nil }

    async let first: Void = dashboard.resumeEndedChatSession(sessionID)
    async let second: Void = dashboard.resumeEndedChatSession(sessionID)
    _ = await (first, second)

    // 3 つ目のクライアントは用意していないので、二重に作ろうとすればエラー表示の VM になる。
    #expect(resumeClient.resumes.count == 1)
    guard case .appServer(let resumed) = try #require(dashboard.sessionNode(id: sessionID)) else {
        Issue.record("chat node expected")
        return
    }
    #expect(resumed.processExit == nil)
    if case .error = resumed.status { Issue.record("the second press created another session: \(resumed.status)") }
}

// 開き直せなかったら差し替えない。終わった会話に理由を出し、再開ボタンを残す。
@Test @MainActor
func resumeEndedChatSession_keepsTheEndedSessionWhenResumingFails() async throws {
    let sessionStore = InMemorySessionStore()
    let spawnClient = CountingResumeStructuredClient()
    // 2 つ目のクライアントが無いので、再開の準備で失敗する。
    let clients = StructuredClientSequence([spawnClient])
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        sessions: sessionStore,
        agentBinaryPaths: [.claudeCode: "/bin/echo"],
        appServerClientFactory: { _, _, _, _, _ in try clients.next() }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    try await waitUntil { await sessionStore.load().contains { $0.id == sessionID } }
    guard case .appServer(let ended) = try #require(dashboard.sessionNode(id: sessionID)) else {
        Issue.record("chat node expected")
        return
    }
    spawnClient.yield(.processExited(exitCode: 1))
    try await waitUntil { ended.processExit != nil }

    await dashboard.resumeEndedChatSession(sessionID)

    guard case .appServer(let current) = try #require(dashboard.sessionNode(id: sessionID)) else {
        Issue.record("chat node expected")
        return
    }
    #expect(current === ended)
    #expect(current.processExit != nil)
    #expect(current.resumeConversationHandler != nil)
    if case .failed = current.restoreState {} else { Issue.record("the failure is not shown: \(current.restoreState)") }
}

// 開き直している間に閉じられたら、新しいプロセスを残さない。
@Test @MainActor
func resumeEndedChatSession_stopsTheNewProcessWhenTheSessionIsClosedMeanwhile() async throws {
    let sessionStore = InMemorySessionStore()
    let spawnClient = CountingResumeStructuredClient()
    let resumeClient = CountingResumeStructuredClient()
    let clients = StructuredClientSequence([spawnClient, resumeClient])
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        sessions: sessionStore,
        agentBinaryPaths: [.claudeCode: "/bin/echo"],
        appServerClientFactory: { _, _, _, _, _ in try clients.next() }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    try await waitUntil { await sessionStore.load().contains { $0.id == sessionID } }
    guard case .appServer(let ended) = try #require(dashboard.sessionNode(id: sessionID)) else {
        Issue.record("chat node expected")
        return
    }
    spawnClient.yield(.processExited(exitCode: 1))
    try await waitUntil { ended.processExit != nil }

    // 新しいプロセスが会話を開き直している途中で止め、その間に閉じ終える。
    let (gate, release) = AsyncStream<Void>.makeStream()
    resumeClient.onResume = { for await _ in gate { break } }
    let resuming = Task { await dashboard.resumeEndedChatSession(sessionID) }
    try await waitUntil { resumeClient.resumes.count == 1 }
    #expect(await dashboard.removeSession(sessionID))
    release.yield()
    await resuming.value

    #expect(dashboard.sessionNode(id: sessionID) == nil)
    #expect(resumeClient.closes == 1)
}
