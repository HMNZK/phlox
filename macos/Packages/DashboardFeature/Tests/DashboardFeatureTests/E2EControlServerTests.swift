import Foundation
import Testing
import AgentDomain
import AppBootstrap
import ControlServer
import HookServer
import MessageStore
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - WP-E3: ControlServer / phlox CLI E2E (S4 / S5)

private func e2eControlServerEnabled() -> Bool {
  ProcessInfo.processInfo.environment["PHLOX_E2E"] == "1"
}

@Suite("E2E ControlServer")
struct E2EControlServerTests {

  // MARK: Test 1 — S4: list / send / read

  @Test(.enabled(if: e2eControlServerEnabled()), .timeLimit(.minutes(1)))
  @MainActor
  func s4_phloxListSendRead() async throws {
    try await withControlContext { ctx in
    let apiURL = "http://127.0.0.1:\(ctx.port)"
    let operatorSessionID = SessionID()
    let operatorToken = "e2e-operator-\(UUID().uuidString)"
    await ctx.tokenStore.register(operatorToken, for: operatorSessionID)

    let list = try await runPhlox(
      args: ["list"],
      apiURL: apiURL,
      token: operatorToken,
      sessionID: operatorSessionID.rawValue.uuidString
    )
    #expect(list.exitCode == 0)
    #expect(list.stdout.contains("alpha"))

    let send = try await runPhlox(
      args: ["send", "--to", "alpha", "--", "ping"],
      apiURL: apiURL,
      token: operatorToken,
      sessionID: operatorSessionID.rawValue.uuidString
    )
    #expect(send.exitCode == 0)

    let echoed = await e2eControlWaitUntil(timeoutNanoseconds: 10_000_000_000) {
      guard let output = ctx.dashboard.sessionOutput(for: ctx.alphaSessionID) else { return false }
      return output.contains("ECHO:") && output.contains("ping")
    }
    let alphaOutput = ctx.dashboard.sessionOutput(for: ctx.alphaSessionID) ?? "<nil>"
    #expect(echoed, "PTY 出力に ping のエコーが現れなかった。sessionOutput=\(alphaOutput)")

    let read = try await runPhlox(
      args: ["read", "--to", "alpha"],
      apiURL: apiURL,
      token: operatorToken,
      sessionID: operatorSessionID.rawValue.uuidString
    )
    #expect(read.exitCode == 0)
    #expect(read.stdout.contains("ECHO:") && read.stdout.contains("ping"))
    }
  }

  // MARK: Test 2 — S4 異常系: 認証・宛先不在

  @Test(.enabled(if: e2eControlServerEnabled()), .timeLimit(.minutes(1)))
  @MainActor
  func s4_invalidTokenAndMissingRecipient() async throws {
    try await withControlContext { ctx in
    let apiURL = "http://127.0.0.1:\(ctx.port)"
    let operatorSessionID = SessionID()

    let badList = try await runPhlox(
      args: ["list"],
      apiURL: apiURL,
      token: "invalid-token",
      sessionID: operatorSessionID.rawValue.uuidString
    )
    #expect(badList.exitCode != 0)

    let operatorToken = "e2e-operator-\(UUID().uuidString)"
    await ctx.tokenStore.register(operatorToken, for: operatorSessionID)

    let badSend = try await runPhlox(
      args: ["send", "--to", "does-not-exist", "--", "x"],
      apiURL: apiURL,
      token: operatorToken,
      sessionID: operatorSessionID.rawValue.uuidString
    )
    #expect(badSend.exitCode != 0)
    }
  }

  // MARK: Test 3 — S5: API spawn と親子

  @Test(.enabled(if: e2eControlServerEnabled()), .timeLimit(.minutes(1)))
  @MainActor
  func s5_apiSpawnRecordsParentAndKillParentEndsChild() async throws {
    try await withControlContext { ctx in
    let apiURL = "http://127.0.0.1:\(ctx.port)"
    let spawn = try await runPhlox(
      args: ["spawn", "--kind", "fake-agent"],
      apiURL: apiURL,
      token: ctx.alphaToken,
      sessionID: ctx.alphaSessionID.rawValue.uuidString
    )
    #expect(spawn.exitCode == 0)

    let childIDString = spawn.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let childUUID = UUID(uuidString: childIDString) else {
      Issue.record("spawn 出力が UUID ではない: \(childIDString)")
      return
    }
    let childID = SessionID(rawValue: childUUID)

    let childReady = await e2eControlWaitUntil(timeoutNanoseconds: 10_000_000_000) {
      guard let child = ctx.dashboard.sessions.first(where: { $0.id == childID }) else { return false }
      return child.parentSessionID == ctx.alphaSessionID && child.status == .idle
    }
    #expect(childReady, "子セッションが生成され親 ID が記録されなかった")

    let grandchildID = try await ctx.dashboard.spawnNewSession(ref: .custom("fake-agent"), from: childID)
    let grandchildReady = await e2eControlWaitUntil(timeoutNanoseconds: 10_000_000_000) {
      guard let grandchild = ctx.dashboard.sessions.first(where: { $0.id == grandchildID }) else { return false }
      return grandchild.parentSessionID == childID && grandchild.status == .idle
    }
    #expect(grandchildReady, "孫セッションが生成され親 ID が記録されなかった")

    let kill = try await runPhlox(
      args: ["kill", ctx.alphaSessionID.rawValue.uuidString],
      apiURL: apiURL,
      token: ctx.alphaToken,
      sessionID: ctx.alphaSessionID.rawValue.uuidString
    )
    #expect(kill.exitCode == 0)

    let descendantsRemoved = await e2eControlWaitUntil(timeoutNanoseconds: 10_000_000_000) {
      !ctx.dashboard.sessions.contains(where: { $0.id == childID || $0.id == grandchildID })
    }
    #expect(descendantsRemoved, "親 kill 後に子と孫が一覧から消えなかった")
    }
  }
}

// MARK: - Private harness

@MainActor
private final class E2EControlDashboard: ControlActionDashboard {
  private let dashboard: DashboardViewModel

  init(dashboard: DashboardViewModel) {
    self.dashboard = dashboard
  }

  var controlSessionSummaries: [ControlSessionSummary] {
    dashboard.sessions.map { session in
      ControlSessionSummary(
        id: session.id,
        name: session.name,
        agentID: session.agentRef.id,
        status: session.status,
        workspaceName: session.workspaceName
      )
    }
  }

  func sendMessage(
    to recipient: Recipient,
    text: String,
    submit: Bool,
    from: SessionID?,
    inReplyTo: UUID?,
    images: [ControlImageAttachment]
  ) async -> DashboardViewModel.SendOutcome {
    await dashboard.sendMessage(
      to: recipient,
      text: text,
      submit: submit,
      from: from,
      inReplyTo: inReplyTo,
      images: images
    )
  }

  func spawnSession(
    ref: AgentRef,
    from: SessionID?,
    backend: SessionBackend,
    workingDirectory: String?
  ) async throws -> SessionID {
    try await dashboard.spawnNewSession(
      ref: ref,
      from: from,
      backend: backend,
      workingDirectoryOverride: workingDirectory
    )
  }

  func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool {
    dashboard.isAuthorizedToRemove(id, requester: requester)
  }

  func removeSession(_ id: SessionID) async -> Bool {
    await dashboard.removeSession(id)
  }

  func renameSession(_ id: SessionID, to name: String) {
    dashboard.renameSession(id, to: name)
  }

  func sessionOutput(for id: SessionID) -> String? {
    dashboard.sessionOutput(for: id)
  }

  func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? {
    dashboard.controlMessagesDelta(for: id, since: since)
  }

  func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult {
    await dashboard.waitUntilReady(for: id, timeout: timeout)
  }

  func waitUntilDone(
    for id: SessionID,
    timeout: Duration,
    sentinel: String?
  ) async -> DashboardViewModel.DoneResult {
    await dashboard.waitUntilDone(for: id, timeout: timeout, sentinel: sentinel)
  }

  func listApprovals() async -> [ApprovalDTO] {
    dashboard.controlApprovals().map { approval in
      ApprovalDTO(
        id: approval.id.uuidString,
        sessionID: approval.sessionID.rawValue.uuidString,
        kind: approval.kind,
        prompt: approval.prompt
      )
    }
  }

  func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool {
    await dashboard.respondToControlApproval(idString: id, decisionRawValue: decision.rawValue)
  }

  func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome {
    await dashboard.controlInterruptSession(id)
  }

  func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? {
    dashboard.controlSubAgents(for: id)
  }

  func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? {
    dashboard.controlSubAgentMessages(for: id, subAgentID: subAgentID)
  }

  func sessionUsage(for id: SessionID) -> ControlSessionUsage? {
    dashboard.controlUsage(for: id)
  }
}

@MainActor
private struct E2EControlContext {
  let pty: PTYManager
  let tokenStore: SessionTokenStore
  let dashboard: DashboardViewModel
  let controlDashboard: E2EControlDashboard
  let controlServer: ControlServer
  let port: Int
  let alphaSessionID: SessionID
  let alphaToken: String

  func teardown() async {
    for session in dashboard.sessions {
      await dashboard.removeSession(session.id)
    }
    await pty.terminateAllAndWait(timeout: .seconds(5))
  }
}

@MainActor
private func withControlContext(
  _ body: (E2EControlContext) async throws -> Void
) async throws {
  let ctx = try await makeControlContext()
  do {
    try await body(ctx)
  } catch {
    await ctx.teardown()
    throw error
  }
  await ctx.teardown()
}

@MainActor
private func makeFakeAgentCatalog() -> (AgentCatalog, [String: String]) {
  let descriptor = AgentDescriptor(
    ref: .custom("fake-agent"),
    displayName: "Fake Agent",
    binaryName: "fake-agent",
    symbolName: "terminal",
    colorRGB: AgentRGB(0x66, 0xBB, 0x6A),
    bypassKey: "phlox.bypass.fake-agent",
    launchSpec: AgentLaunchSpec(
      baseArgs: [e2eControlFakeAgentPath()],
      hookKind: .none,
      statusBootstrap: .idleOnSpawnComplete
    )
  )
  return (AgentCatalog(customDescriptors: [descriptor]), ["fake-agent": "/bin/bash"])
}

@MainActor
private func makeControlContext() async throws -> E2EControlContext {
  let (catalog, customPaths) = makeFakeAgentCatalog()
  let tokenStore = SessionTokenStore()
  let pty = PTYManager()
  let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
  let handler = ControlActionHandler()

  let controlServer = ControlServer(tokenStore: tokenStore, agentCatalog: catalog) { request in
    await handler.handle(request)
  }
  let port = try await controlServer.start(preferredPort: 0)
  let controlURL = URL(string: "http://127.0.0.1:\(port)")!

  let workspace = URL(fileURLWithPath: e2eControlTempDirectory(), isDirectory: true)
  let environment = AppEnvironment(
    pty: pty,
    hook: MockHookServer(events: hookStream),
    hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
    claudeSettingsURL: URL(fileURLWithPath: "/tmp/phlox-e2e-hooks.json"),
    hookDispatcherPath: "/tmp/phlox-e2e-dispatcher.sh",
    claudeBinaryPath: "/usr/bin/false",
    pathEnvironment: "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
    workspaceDirectory: workspace,
    customAgentBinaryPaths: customPaths,
    agentCatalog: catalog,
    controlURL: controlURL,
    tokenStore: tokenStore,
    messages: MockMessageStore(),
    cliPath: phloxCLIPath()
  )

  let dashboard = DashboardViewModel(environment: environment)
  let controlDashboard = E2EControlDashboard(dashboard: dashboard)
  handler.dashboard = controlDashboard
  await dashboard.start()

  let alphaSessionID = try await dashboard.spawnNewSession(ref: .custom("fake-agent"))
  dashboard.renameSession(alphaSessionID, to: "alpha")

  guard let alphaVM = dashboard.sessions.first(where: { $0.id == alphaSessionID }) else {
    throw E2EControlError.alphaSessionMissing
  }
  alphaVM.terminalCoordinator.onResize(80, 24)

  let ready = await e2eControlWaitUntil(timeoutNanoseconds: 10_000_000_000) {
    alphaVM.status == .idle
  }
  guard ready else { throw E2EControlError.alphaNotReady }

  guard let alphaToken = await tokenStore.token(for: alphaSessionID) else {
    throw E2EControlError.alphaTokenMissing
  }

  return E2EControlContext(
    pty: pty,
    tokenStore: tokenStore,
    dashboard: dashboard,
    controlDashboard: controlDashboard,
    controlServer: controlServer,
    port: port,
    alphaSessionID: alphaSessionID,
    alphaToken: alphaToken
  )
}

private enum E2EControlError: Error {
  case alphaSessionMissing
  case alphaNotReady
  case alphaTokenMissing
}

private struct PhloxRunResult {
  let exitCode: Int32
  let stdout: String
  let stderr: String
}

private struct HTTPSpawnResponse {
  let statusCode: Int
  let bodyJSON: [String: Any]?
}

private func phloxCLIPath() -> String {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // DashboardFeatureTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // DashboardFeature
    .deletingLastPathComponent()   // Packages
    .deletingLastPathComponent()   // リポジトリルート
    .appendingPathComponent("scripts/phlox")
    .path
}

private func e2eControlFakeAgentPath() -> String {
  let fixturesDir = (#filePath as NSString).deletingLastPathComponent + "/Fixtures"
  return (fixturesDir as NSString).appendingPathComponent("fake-agent.sh")
}

private func e2eControlTempDirectory() -> String {
  let dir = (NSTemporaryDirectory() as NSString)
    .appendingPathComponent("phlox-e2e-control-\(UUID().uuidString)")
  try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
  return dir
}

private func e2eControlChildEnvironment(extra: [String: String] = [:]) -> [String: String] {
  let basePath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
  let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
  var env: [String: String] = [
    "PATH": inherited.isEmpty ? basePath : "\(basePath):\(inherited)",
    "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
    "USER": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
    "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
    "TERM": "xterm-256color",
  ]
  for (key, value) in extra { env[key] = value }
  return env
}

@MainActor
private func e2eControlWaitUntil(
  timeoutNanoseconds: UInt64,
  pollIntervalNanoseconds: UInt64 = 50_000_000,
  _ condition: @escaping () async -> Bool
) async -> Bool {
  var elapsed: UInt64 = 0
  while await !condition() {
    guard elapsed < timeoutNanoseconds else { return false }
    try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    elapsed += pollIntervalNanoseconds
  }
  return true
}

// MainActor 上で waitUntilExit すると、phlox → ControlServer → MainActor 隔離の
// DashboardViewModel という経路が永遠に実行されずデッドロックする。
// プロセスの実行と終了待ちは必ず MainActor 外（detached task）で行う。
private func runPhlox(
  args: [String],
  apiURL: String,
  token: String,
  sessionID: String
) async throws -> PhloxRunResult {
  let phloxPath = phloxCLIPath()
  let environment = e2eControlChildEnvironment(extra: [
    "PHLOX_API_URL": apiURL,
    "PHLOX_TOKEN": token,
    "PHLOX_SESSION_ID": sessionID,
  ])
  return try await Task.detached {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [phloxPath] + args
    process.environment = environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return PhloxRunResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
  }.value
}

private func postSpawn(port: Int, token: String, kind: String) async throws -> HTTPSpawnResponse {
  var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sessions")!)
  request.httpMethod = "POST"
  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = Data("{\"kind\":\"\(kind)\"}".utf8)

  let (data, response) = try await URLSession.shared.data(for: request)
  let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
  let bodyJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  return HTTPSpawnResponse(statusCode: statusCode, bodyJSON: bodyJSON)
}
