import Foundation
import Testing
import AgentDomain
import HookServer
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// ADR 0221: 24 時間使われていないチャットはエージェントのプロセスだけを止め、「この会話から再開」で開き直す。

@MainActor
private func makeIdleDashboard(_ clients: [CountingResumeStructuredClient]) async throws -> (DashboardViewModel, SessionID, InMemorySessionStore) {
    let sessionStore = InMemorySessionStore()
    let sequence = StructuredClientSequence(clients)
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        sessions: sessionStore,
        agentBinaryPaths: [.claudeCode: "/bin/echo"],
        appServerClientFactory: { _, _, _, _, _ in try sequence.next() }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    try await waitUntil { await sessionStore.load().contains { $0.id == sessionID } }
    return (dashboard, sessionID, sessionStore)
}

@MainActor
private func chat(_ dashboard: DashboardViewModel, _ id: SessionID) throws -> ChatSessionViewModel {
    guard case .appServer(let chat) = try #require(dashboard.sessionNode(id: id)) else {
        throw IdleSuspendTestError.notChat
    }
    return chat
}

private enum IdleSuspendTestError: Error { case notChat }

private let dayAndAMinute: TimeInterval = DashboardViewModel.idleSuspendAfter + 60

@Test @MainActor
func idleChatIsSuspendedWithoutAttentionAndResumesTheSameConversation() async throws {
    let spawnClient = CountingResumeStructuredClient()
    let resumeClient = CountingResumeStructuredClient()
    let (dashboard, sessionID, _) = try await makeIdleDashboard([spawnClient, resumeClient])
    let idle = try chat(dashboard, sessionID)
    try await waitUntil { idle.canSuspendForIdle }

    await dashboard.suspendIdleChatSessions(now: Date().addingTimeInterval(dayAndAMinute))

    #expect(idle.processExit == ChatProcessExit(exitCode: nil, suspendedForIdle: true))
    #expect(spawnClient.closes == 1)
    #expect(!idle.hasUnseenCompletion)
    #expect(dashboard.unseenCompletionCount == 0)
    #expect(try chat(dashboard, sessionID) === idle)

    await dashboard.resumeEndedChatSession(sessionID)
    let resumed = try chat(dashboard, sessionID)
    #expect(resumed !== idle)
    #expect(resumed.processExit == nil)
    #expect(resumeClient.resumes == [sessionID.rawValue.uuidString.lowercased()])
    #expect(!idle.hasUnseenCompletion)
    #expect(dashboard.unseenCompletionCount == 0)
}

@Test @MainActor
func chatIsNotSuspendedWithin24HoursOrWhileShownOnScreen() async throws {
    let client = CountingResumeStructuredClient()
    let (dashboard, sessionID, _) = try await makeIdleDashboard([client])
    let idle = try chat(dashboard, sessionID)
    try await waitUntil { idle.canSuspendForIdle }

    await dashboard.suspendIdleChatSessions(now: Date().addingTimeInterval(DashboardViewModel.idleSuspendAfter - 60))
    #expect(idle.processExit == nil)

    // 画面に表示された時刻から数え直す（出力から 24 時間たっていても、表示から 24 時間たつまでは止めない）。
    dashboard.lastViewedAt[sessionID] = Date().addingTimeInterval(3600)
    await dashboard.suspendIdleChatSessions(now: Date().addingTimeInterval(dayAndAMinute))
    #expect(idle.processExit == nil)
    #expect(client.closes == 0)
    await dashboard.suspendIdleChatSessions(now: Date().addingTimeInterval(3600 + dayAndAMinute))
    #expect(idle.processExit?.suspendedForIdle == true)
}

@Test @MainActor
func chatWaitingForAnAnswerIsNotSuspended() async throws {
    let client = CountingResumeStructuredClient()
    let (dashboard, sessionID, _) = try await makeIdleDashboard([client])
    let waiting = try chat(dashboard, sessionID)
    try await waitUntil { waiting.canSuspendForIdle }
    client.yield(.turnStarted)
    try await waitUntil { waiting.showsProcessingIndicator }
    client.yield(.userQuestionRequested(requestId: "q1", questions: [ChatUserQuestion(question: "どちら?", header: "選択", options: [], multiSelect: false)]))
    try await waitUntil { SessionNode.appServer(waiting).tabDisplayState == .question }

    await dashboard.suspendIdleChatSessions(now: Date().addingTimeInterval(dayAndAMinute))

    #expect(waiting.processExit == nil)
    #expect(client.closes == 0)
}

// 画面（常駐側の写し）から知らせた表示中のセッションが、エラーなしで常駐側に届く。
@Test @MainActor
func sessionsViewedFromTheScreenReachTheRuntimeWithoutError() async throws {
    let client = CountingResumeStructuredClient()
    let (owned, sessionID, _) = try await makeIdleDashboard([client])
    let screen = try DashboardViewModel(projection: owned.makeRuntimeSnapshot()) { try await owned.performRuntimeCommand($0) }
    screen.noteSessionsViewed([sessionID])
    try await waitUntil { owned.lastViewedAt[sessionID] != nil }
    try await Task.sleep(for: .milliseconds(50))
    #expect(screen.runtimeCommandError == nil)
}

// 更新前の常駐側は知らせを解読できずに断る。利用者の操作ではないので警告を出さない。
@Test @MainActor
func sessionsViewedRejectedByAnOlderRuntimeRaisesNoAlert() async throws {
    let client = CountingResumeStructuredClient()
    let (owned, sessionID, _) = try await makeIdleDashboard([client])
    var rejected = 0
    let screen = try DashboardViewModel(projection: owned.makeRuntimeSnapshot()) { command in
        if case .sessionsViewed = command { rejected += 1; throw URLError(.badServerResponse) }
        return try await owned.performRuntimeCommand(command)
    }
    screen.noteSessionsViewed([sessionID])
    try await waitUntil { rejected == 1 }
    try await Task.sleep(for: .milliseconds(50))
    #expect(screen.runtimeCommandError == nil)
}

// Cursor はターンごとにプロセスが終わるので止めない。端末セッションも触らない。
@Test @MainActor
func cursorChatsAndTerminalSessionsAreNotSuspended() async throws {
    let cursorClient = CountingResumeStructuredClient()
    let sequence = StructuredClientSequence([cursorClient])
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        sessions: InMemorySessionStore(),
        agentBinaryPaths: [.claudeCode: "/bin/echo", .cursor: "/bin/echo"],
        appServerClientFactory: { _, _, _, _, _ in try sequence.next() }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    let terminalID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .pty)
    let cursorID = try await dashboard.spawnNewSession(kind: .cursor, backend: .appServer)
    let cursor = try chat(dashboard, cursorID)
    try await waitUntil { cursor.status == .idle }
    #expect(!cursor.canSuspendForIdle)

    await dashboard.suspendIdleChatSessions(now: Date().addingTimeInterval(dayAndAMinute))

    #expect(cursor.processExit == nil)
    #expect(cursorClient.closes == 0)
    guard case .pty(let terminal) = try #require(dashboard.sessionNode(id: terminalID)) else {
        Issue.record("terminal node expected")
        return
    }
    #expect(terminal.status != .completed(exitCode: 0))
}

@Test @MainActor
func runningChatIsNotSuspended() async throws {
    let client = CountingResumeStructuredClient()
    let (dashboard, sessionID, _) = try await makeIdleDashboard([client])
    let running = try chat(dashboard, sessionID)
    try await waitUntil { running.canSuspendForIdle }
    client.yield(.turnStarted)
    try await waitUntil { running.showsProcessingIndicator }

    await dashboard.suspendIdleChatSessions(now: Date().addingTimeInterval(dayAndAMinute))

    #expect(running.processExit == nil)
    #expect(client.closes == 0)
}

@Test
func idleSuspendedExitRoundTripsAndOldSnapshotsDecode() throws {
    let suspended = ChatProcessExit(exitCode: nil, suspendedForIdle: true)
    #expect(try JSONDecoder().decode(ChatProcessExit.self, from: JSONEncoder().encode(suspended)) == suspended)
    #expect(try JSONDecoder().decode(ChatProcessExit.self, from: Data(#"{"exitCode":3}"#.utf8)) == ChatProcessExit(exitCode: 3))
}

// 単一表示で出ている会話を「表示中」とする。プロジェクトに入っていない会話と左右の両側を含め、ファイル等のタブと新規チャット画面は含めない。
@Test @MainActor
func displayedChatsAreTheChatsActuallyOnScreen() {
    let router = AppRouter()
    let unassigned = SessionID()
    router.selectedSession = unassigned
    #expect(router.displayedChatSessionIDs { _ in nil } == [unassigned])

    // プロジェクトを選ばずにプロジェクト内の会話を選んだときは、その会話のプロジェクトの配置で判断する。
    let project = ProjectID()
    let a = SessionID()
    let b = SessionID()
    router.tabs.updateLayout(for: project) { $0.select(.chat(a)) }
    router.selectedSession = a
    #expect(router.selectedProjectID == nil)
    #expect(router.displayedChatSessionIDs { _ in project } == [a])

    router.selectTab(.chat(a), in: project)
    router.splitRight(.chat(b), in: project, chats: [.chat(a), .chat(b)])
    router.selectTab(.chat(a), in: project)
    #expect(router.displayedChatSessionIDs { _ in project } == [a, b])

    router.tabs.updateLayout(for: project) { $0.open(.file("/tmp/a.swift")) }
    #expect(router.displayedChatSessionIDs { _ in project } == [b])

    router.showNewChat(projectID: project)
    #expect(router.displayedChatSessionIDs { _ in project } == [])
}

// 画面（常駐側の写し）から休止した会話を再開すると、写しが同じ会話として新しい状態を受け取る。
@Test @MainActor
func resumingFromTheScreenKeepsTheProjectionInSync() async throws {
    let spawnClient = CountingResumeStructuredClient()
    let resumeClient = CountingResumeStructuredClient()
    let (owned, sessionID, _) = try await makeIdleDashboard([spawnClient, resumeClient])
    let idle = try chat(owned, sessionID)
    try await waitUntil { idle.canSuspendForIdle }
    await owned.suspendIdleChatSessions(now: Date().addingTimeInterval(dayAndAMinute))
    let screen = try DashboardViewModel(projection: owned.makeRuntimeSnapshot()) { try await owned.performRuntimeCommand($0) }
    #expect(try chat(screen, sessionID).processExit?.suspendedForIdle == true)

    await screen.resumeEndedChatSession(sessionID)
    try screen.applyRuntimeSnapshot(owned.makeRuntimeSnapshot())

    #expect(try chat(screen, sessionID).processExit == nil)
    #expect(screen.runtimeCommandError == nil)
}
