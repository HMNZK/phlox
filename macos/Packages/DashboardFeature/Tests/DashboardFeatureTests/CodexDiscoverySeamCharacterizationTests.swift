// Codex discovery controller seam 特性化（Run 2 / task-6）
// DashboardViewModel.swift:1665-1821 の観測可能な振る舞いのうち、既存テストが覆っていない差分のみ。

import AgentDomain
import Foundation
import HookServer
import PTYKit
import Testing
@testable import DashboardFeature

// MARK: - Helpers

private func makeTemporaryCodexHomeForSeamTests() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-codex-seam-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanupTemporaryCodexHomeForSeamTests(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func fixedDateForSeamTests(_ date: Date) -> @Sendable () -> Date {
    { date }
}

private func codexRolloutISOTimestampForSeamTests(for date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func writeCodexRolloutForSeamTests(
    codexHome: URL,
    date: Date,
    sessionID: String,
    cwd: String,
    timestamp: Date
) throws {
    let dayDirectory = CodexSessionDiscovery.dayDirectory(
        for: date,
        under: codexHome.appendingPathComponent("sessions", isDirectory: true)
    )
    try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
    let filenameTimestamp = codexRolloutISOTimestampForSeamTests(for: timestamp)
        .replacingOccurrences(of: ":", with: "-")
    let filename = "rollout-\(filenameTimestamp)-\(sessionID.lowercased()).jsonl"
    let line = """
    {"type":"session_meta","payload":{"id":"\(sessionID)","cwd":"\(cwd)","timestamp":"\(codexRolloutISOTimestampForSeamTests(for: timestamp))"}}
    """
    try line.write(to: dayDirectory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
}

@MainActor
private func makeCodexDiscoveryDashboard(
    codexHome: URL,
    sessionStore: InMemorySessionStore,
    workspaceURL: URL,
    spawnTime: Date,
    retryInterval: Duration = .milliseconds(50),
    maxRetryDuration: Duration = .seconds(2),
    agentBinaryPaths: [AgentKind: String] = [.codex: "/usr/local/bin/codex"]
) -> (dashboard: DashboardViewModel, environment: AppEnvironment) {
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        sessions: sessionStore,
        workspaceDirectory: workspaceURL,
        codexHome: codexHome,
        agentBinaryPaths: agentBinaryPaths
    )
    let dashboard = DashboardViewModel(
        environment: environment,
        codexDiscoveryRetryInterval: retryInterval,
        codexDiscoveryMaxRetryDuration: maxRetryDuration,
        codexDiscoveryNow: fixedDateForSeamTests(spawnTime)
    )
    return (dashboard, environment)
}

// MARK: - Characterization tests

@Test @MainActor
func characterization_codexRestoreWithExistingResumeID_skipsRolloutDiscovery() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForSeamTests()
    defer { cleanupTemporaryCodexHomeForSeamTests(codexHome) }

    let sessionID = SessionID()
    let workingDirectory = workspaceURL
        .appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
        .path
    try FileManager.default.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)

    let spawnTime = Date(timeIntervalSince1970: 1_740_001_000)
    let existingResumeID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    let sessionStore = InMemorySessionStore([
        makePersistedSessionDescriptor(
            id: sessionID,
            kind: .codex,
            workingDirectory: workingDirectory,
            startedAt: spawnTime,
            resumeID: existingResumeID
        ),
    ])

    let (dashboard, _) = makeCodexDiscoveryDashboard(
        codexHome: codexHome,
        sessionStore: sessionStore,
        workspaceURL: workspaceURL,
        spawnTime: spawnTime
    )
    await dashboard.start()

    #expect(dashboard.sessions.contains { $0.id == sessionID })
    #expect(dashboard.codexDiscoveryTaskCountForTesting == 0)

    let unclaimedNativeID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    try writeCodexRolloutForSeamTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: unclaimedNativeID,
        cwd: workingDirectory,
        timestamp: spawnTime
    )

    dashboard.sessionNodes.first(where: { $0.id == sessionID })?.pty?.onInputSubmitted?()

    try await Task.sleep(for: .milliseconds(200))

    #expect(dashboard.codexDiscoveryTaskCountForTesting == 0)
    let saved = await sessionStore.load().first(where: { $0.id == sessionID })
    #expect(saved?.resumeID == existingResumeID)
}

@Test @MainActor
func characterization_secondCodexSession_skipsResumeIDAlreadyClaimedByFirstSession() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForSeamTests()
    defer { cleanupTemporaryCodexHomeForSeamTests(codexHome) }

    let sessionStore = InMemorySessionStore()
    let spawnTime = Date(timeIntervalSince1970: 1_740_001_100)
    let (dashboard, environment) = makeCodexDiscoveryDashboard(
        codexHome: codexHome,
        sessionStore: sessionStore,
        workspaceURL: workspaceURL,
        spawnTime: spawnTime
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    let firstSessionID = try #require(dashboard.sessions.first?.id)
    let firstWorkingDirectory = environment.sessionWorkspaceDirectory(for: firstSessionID).path

    let claimedNativeID = "cccccccc-cccc-cccc-cccc-cccccccccccc"
    try writeCodexRolloutForSeamTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: claimedNativeID,
        cwd: firstWorkingDirectory,
        timestamp: spawnTime
    )

    #expect(await waitUntil(timeoutNanoseconds: 2_000_000_000) {
        await sessionStore.load().first(where: { $0.id == firstSessionID })?.resumeID == claimedNativeID
    })

    try await dashboard.spawnNewSession(kind: .codex)
    let secondSessionID = try #require(dashboard.sessions.last?.id)
    let secondWorkingDirectory = environment.sessionWorkspaceDirectory(for: secondSessionID).path

    try writeCodexRolloutForSeamTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: claimedNativeID,
        cwd: secondWorkingDirectory,
        timestamp: spawnTime
    )

    try await Task.sleep(for: .milliseconds(400))

    let secondSaved = await sessionStore.load().first(where: { $0.id == secondSessionID })
    #expect(secondSaved?.resumeID == nil)
}

@Test @MainActor
func characterization_rolloutDiscovery_clearsTaskAfterSuccessfulPersist() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForSeamTests()
    defer { cleanupTemporaryCodexHomeForSeamTests(codexHome) }

    let sessionStore = InMemorySessionStore()
    let spawnTime = Date(timeIntervalSince1970: 1_740_001_200)
    let (dashboard, environment) = makeCodexDiscoveryDashboard(
        codexHome: codexHome,
        sessionStore: sessionStore,
        workspaceURL: workspaceURL,
        spawnTime: spawnTime
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    let sessionID = try #require(dashboard.sessions.first?.id)
    let workingDirectory = environment.sessionWorkspaceDirectory(for: sessionID).path

    #expect(dashboard.codexDiscoveryTaskCountForTesting == 1)

    let nativeID = "dddddddd-dddd-dddd-dddd-dddddddddddd"
    try writeCodexRolloutForSeamTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: nativeID,
        cwd: workingDirectory,
        timestamp: spawnTime
    )

    #expect(await waitUntil(timeoutNanoseconds: 2_000_000_000) {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == nativeID
    })

    #expect(dashboard.codexDiscoveryTaskCountForTesting == 0)
}

@Test @MainActor
func characterization_claudeSpawn_doesNotStartCodexRolloutDiscovery() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForSeamTests()
    defer { cleanupTemporaryCodexHomeForSeamTests(codexHome) }

    let sessionStore = InMemorySessionStore()
    let spawnTime = Date(timeIntervalSince1970: 1_740_001_300)
    let (dashboard, environment) = makeCodexDiscoveryDashboard(
        codexHome: codexHome,
        sessionStore: sessionStore,
        workspaceURL: workspaceURL,
        spawnTime: spawnTime,
        agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"]
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .claudeCode)
    #expect(dashboard.codexDiscoveryTaskCountForTesting == 0)

    let sessionID = try #require(dashboard.sessions.first?.id)
    let workingDirectory = environment.sessionWorkspaceDirectory(for: sessionID).path
    try writeCodexRolloutForSeamTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
        cwd: workingDirectory,
        timestamp: spawnTime
    )

    dashboard.sessionNodes.first(where: { $0.id == sessionID })?.pty?.onInputSubmitted?()
    try await Task.sleep(for: .milliseconds(200))

    #expect(dashboard.codexDiscoveryTaskCountForTesting == 0)
}
