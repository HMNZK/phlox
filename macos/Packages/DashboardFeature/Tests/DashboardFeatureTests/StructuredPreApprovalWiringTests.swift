import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// task-13: Codex app-server 起動 args に reasoning summary 設定が含まれること。
@Test
func appEnvironmentCodexAppServerProcessArguments_includeReasoningSummaryOverride() {
    #expect(
        AppEnvironment.codexAppServerProcessArguments()
            == ["app-server", "-c", "model_reasoning_summary=detailed"]
    )
}

@Test
@MainActor
func appEnvironmentCodexFactoryPassesReasoningSummaryArgsToProcess() async throws {
    let tempDirectory = try makeTemporaryDirectory(named: "codex-app-server-args")
    let argsURL = tempDirectory.appendingPathComponent("codex-args.txt")
    let executableURL = tempDirectory.appendingPathComponent("fake-codex.sh")
    try writeExecutableScript(
        """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(argsURL.path)"
        """,
        to: executableURL
    )

    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() }
    )
    _ = try await environment.structuredClientFactory(
        .builtin(.codex),
        executableURL.path,
        tempDirectory.path,
        [:],
        nil
    )

    try await assertEventuallyFileExists(argsURL)
    let argsText = try String(contentsOf: argsURL, encoding: .utf8)
    #expect(argsText == "app-server\n-c\nmodel_reasoning_summary=detailed\n")
}

// task-8: Claude/Cursor 送信は「常に自動承認（handler を呼ばない）」に変更された。
// これらのテストは「承認 handler（ChatApprovalBroker への request）が呼ばれない」
// ＝バナーが出ないこと、かつツール権限付与（Claude: acceptEdits + allowedTools /
// Cursor: -f）が維持されることを検証する。

@Test
@MainActor
func appEnvironmentClaudeAutoApprovesWithoutInvokingApprovalHandler() async throws {
    let tempDirectory = try makeTemporaryDirectory(named: "claude-auto-approve")
    let argsURL = tempDirectory.appendingPathComponent("claude-args.txt")
    let markerURL = tempDirectory.appendingPathComponent("stdin-marker.txt")
    let executableURL = tempDirectory.appendingPathComponent("fake-claude.sh")
    try writeExecutableScript(
        """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(argsURL.path)"
        while IFS= read -r line; do
          printf '%s' "$line" > "\(markerURL.path)"
        done
        """,
        to: executableURL
    )

    let recorder = ApprovalCallRecorder()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() }
    )
    let client = try await environment.structuredClientFactory(
        .builtin(.claudeCode),
        executableURL.path,
        tempDirectory.path,
        [:],
        recordingApprovalHandler(recorder)
    )

    await client.start()
    try await client.turnStart([.text("write a file")])

    // 自動承認なのでバナー経路（handler）を通らずにターンが submit される。
    try await assertEventuallyFileExists(markerURL)
    #expect(recorder.wasCalled == false)

    // ツール権限付与（acceptEdits + allowedTools）が維持されていること。
    let argsText = try String(contentsOf: argsURL, encoding: .utf8)
    #expect(argsText.contains("--permission-mode\nacceptEdits\n"))
    #expect(argsText.contains("--allowedTools\nBash,Read,Glob,Grep,LS,Edit,Write,MultiEdit\n"))

    var iterator = client.events.makeAsyncIterator()
    #expect(await iterator.next() == .turnStarted)
    await client.close()
}

@Test
@MainActor
func appEnvironmentCursorAutoApprovesWithForceWithoutInvokingApprovalHandler() async throws {
    let tempDirectory = try makeTemporaryDirectory(named: "cursor-auto-approve")
    let argsURL = tempDirectory.appendingPathComponent("cursor-args.txt")
    let markerURL = tempDirectory.appendingPathComponent("run-marker.txt")
    let executableURL = tempDirectory.appendingPathComponent("fake-cursor.sh")
    try writeExecutableScript(
        """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(argsURL.path)"
        printf 'ran' > "\(markerURL.path)"
        printf '{"type":"result","subtype":"success","session_id":"cursor-test"}\\n'
        """,
        to: executableURL
    )

    let recorder = ApprovalCallRecorder()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() }
    )
    let client = try await environment.structuredClientFactory(
        .builtin(.cursor),
        executableURL.path,
        tempDirectory.path,
        [:],
        recordingApprovalHandler(recorder)
    )

    await client.start()
    try await client.turnStart([.text("write a file")])

    // 自動承認なのでバナー経路（handler）を通らずにプロセスが実行される。
    #expect(FileManager.default.fileExists(atPath: markerURL.path))
    #expect(recorder.wasCalled == false)

    // pre-approved 相当（force）が付与されていること。
    let argsText = try String(contentsOf: argsURL, encoding: .utf8)
    #expect(argsText.contains("-f\n"))

    var iterator = client.events.makeAsyncIterator()
    #expect(await iterator.next() == .turnStarted)
    #expect(await iterator.next() == .turnCompleted(nativeSessionId: "cursor-test"))
    await client.close()
}

// task-10 成功基準1/3: Claude で model のみ変更しても、次 turnStart の respawn args に
// 選択 model が反映され、かつ permission（既定 bypassPermissions）が保持される（置換セマンティクスで
// task-8 のツール権限が外れないことの回帰防止）。
@Test
@MainActor
func chatSessionViewModelClaudeModelSelectionRespawnsWithModelKeepingPermission() async throws {
    let tempDirectory = try makeTemporaryDirectory(named: "claude-vm-model")
    let argsURL = tempDirectory.appendingPathComponent("claude-args.txt")
    let markerURL = tempDirectory.appendingPathComponent("stdin-marker.txt")
    let executableURL = tempDirectory.appendingPathComponent("fake-claude.sh")
    try writeExecutableScript(
        """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(argsURL.path)"
        while IFS= read -r line; do
          printf '%s' "$line" > "\(markerURL.path)"
        done
        """,
        to: executableURL
    )

    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() }
    )
    let client = try await environment.structuredClientFactory(
        .builtin(.claudeCode),
        executableURL.path,
        tempDirectory.path,
        [:],
        nil
    )
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: tempDirectory.path
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    #expect(vm.availableSpawnAgentModels == ["opus", "sonnet", "fable", "haiku"])

    await vm.setSpawnAgentModel("opus")
    try await vm.sendText("write a file", submit: true)

    try await assertEventuallyFileExists(markerURL)
    let argsText = try String(contentsOf: argsURL, encoding: .utf8)
    #expect(argsText.contains("--model\nopus\n"))
    #expect(argsText.contains("--permission-mode\nbypassPermissions\n"))
    #expect(argsText.contains("--effort\nhigh\n"))
    #expect(argsText.contains("--allowedTools\nBash,Read,Glob,Grep,LS,Edit,Write,MultiEdit\n"))

    await vm.terminate()
}

// task-10 成功基準4: 選択は codexSettingsDidChange（永続経路）へフルスナップショットで通知される。
@Test
@MainActor
func chatSessionViewModelClaudeSelectionEmitsPersistableSnapshot() async throws {
    let tempDirectory = try makeTemporaryDirectory(named: "claude-vm-persist")
    let executableURL = tempDirectory.appendingPathComponent("fake-claude.sh")
    try writeExecutableScript(
        """
        #!/bin/sh
        while IFS= read -r line; do :; done
        """,
        to: executableURL
    )

    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() }
    )
    let client = try await environment.structuredClientFactory(
        .builtin(.claudeCode),
        executableURL.path,
        tempDirectory.path,
        [:],
        nil
    )
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: tempDirectory.path
    )
    var captured: CodexAppServerSessionSettings?
    vm.codexSettingsDidChange = { captured = $0 }

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    await vm.setSpawnAgentModel("sonnet")

    #expect(captured?.selectedModel == "sonnet")
    #expect(captured?.selectedPermissionProfile == "bypassPermissions")
    #expect(captured?.selectedEffort == "high")

    await vm.terminate()
}

// task-10 成功基準4: 復元時に永続設定（model/permission）を状態へ戻し、次 turn の args に反映する。
@Test
@MainActor
func chatSessionViewModelClaudeRestoreReappliesPersistedModelAndPermission() async throws {
    let tempDirectory = try makeTemporaryDirectory(named: "claude-vm-restore")
    let argsURL = tempDirectory.appendingPathComponent("claude-args.txt")
    let markerURL = tempDirectory.appendingPathComponent("stdin-marker.txt")
    let executableURL = tempDirectory.appendingPathComponent("fake-claude.sh")
    try writeExecutableScript(
        """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(argsURL.path)"
        while IFS= read -r line; do
          printf '%s' "$line" > "\(markerURL.path)"
        done
        """,
        to: executableURL
    )

    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() }
    )
    let client = try await environment.structuredClientFactory(
        .builtin(.claudeCode),
        executableURL.path,
        tempDirectory.path,
        [:],
        nil
    )
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: tempDirectory.path
    )

    await vm.restore(
        threadId: "claude-session-1",
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write"),
        persistedSettings: CodexAppServerSessionSettings(
            selectedModel: "opus",
            selectedPermissionProfile: "plan"
        )
    )

    #expect(vm.selectedModel == "opus")
    #expect(vm.selectedPermissionProfile == "bypassPermissions")
    #expect(vm.isPlanMode)

    try await vm.sendText("continue", submit: true)
    try await assertEventuallyFileExists(markerURL)
    let argsText = try String(contentsOf: argsURL, encoding: .utf8)
    #expect(argsText.contains("--model\nopus\n"))
    #expect(argsText.contains("--permission-mode\nplan\n"))
    #expect(argsText.contains("--effort\nhigh\n"))

    await vm.terminate()
}

// task-22: Claude で effort のみ変更しても model/permission が保持され respawn args に反映される。
@Test
@MainActor
func chatSessionViewModelClaudeEffortSelectionRespawnsWithEffortKeepingModelAndPermission() async throws {
    let tempDirectory = try makeTemporaryDirectory(named: "claude-vm-effort")
    let argsURL = tempDirectory.appendingPathComponent("claude-args.txt")
    let markerURL = tempDirectory.appendingPathComponent("stdin-marker.txt")
    let executableURL = tempDirectory.appendingPathComponent("fake-claude.sh")
    try writeExecutableScript(
        """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(argsURL.path)"
        while IFS= read -r line; do
          printf '%s' "$line" > "\(markerURL.path)"
        done
        """,
        to: executableURL
    )

    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() }
    )
    let client = try await environment.structuredClientFactory(
        .builtin(.claudeCode),
        executableURL.path,
        tempDirectory.path,
        [:],
        nil
    )
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: tempDirectory.path
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    #expect(vm.claudeEffortLevels == ["low", "medium", "high", "xhigh", "max"])

    await vm.setSpawnAgentEffort("low")
    try await vm.sendText("write a file", submit: true)

    try await assertEventuallyFileExists(markerURL)
    let argsText = try String(contentsOf: argsURL, encoding: .utf8)
    #expect(argsText.contains("--model\nopus\n"))
    #expect(argsText.contains("--permission-mode\nbypassPermissions\n"))
    #expect(argsText.contains("--effort\nlow\n"))

    await vm.terminate()
}

// task-22: Cursor セッションでは effort 候補が空（メニュー非表示の契約）。
@Test
@MainActor
func chatSessionViewModelCursorHasNoEffortLevels() async throws {
    let tempDirectory = try makeTemporaryDirectory(named: "cursor-vm-effort-levels")
    let executableURL = tempDirectory.appendingPathComponent("fake-cursor.sh")
    try writeExecutableScript(
        """
        #!/bin/sh
        printf '{"type":"result","subtype":"success","session_id":"cursor-test"}\\n'
        """,
        to: executableURL
    )

    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() }
    )
    let client = try await environment.structuredClientFactory(
        .builtin(.cursor),
        executableURL.path,
        tempDirectory.path,
        [:],
        nil
    )
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: tempDirectory.path,
        spawnAgentModelsProvider: { ["gpt-5.2"] }
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(vm.claudeEffortLevels.isEmpty)

    await vm.terminate()
}

// task-10 成功基準2/3: Cursor は model/mode 選択が次ターン one-shot spawn の args に反映される（-f 維持）。
@Test
@MainActor
func chatSessionViewModelCursorSelectionAppliesModelAndModeOnNextTurn() async throws {
    let tempDirectory = try makeTemporaryDirectory(named: "cursor-vm-model")
    let argsURL = tempDirectory.appendingPathComponent("cursor-args.txt")
    let executableURL = tempDirectory.appendingPathComponent("fake-cursor.sh")
    try writeExecutableScript(
        """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(argsURL.path)"
        printf '{"type":"result","subtype":"success","session_id":"cursor-test"}\\n'
        """,
        to: executableURL
    )

    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() }
    )
    let client = try await environment.structuredClientFactory(
        .builtin(.cursor),
        executableURL.path,
        tempDirectory.path,
        [:],
        nil
    )
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: tempDirectory.path,
        spawnAgentModelsProvider: { ["gpt-5.2"] }
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    #expect(vm.availableSpawnAgentModels == ["gpt-5.2"])

    await vm.setSpawnAgentModel("gpt-5.2")
    await vm.setSpawnAgentPermission("plan")
    try await vm.sendText("write a file", submit: true)

    try await assertEventuallyFileExists(argsURL)
    let argsText = try String(contentsOf: argsURL, encoding: .utf8)
    #expect(argsText.contains("--model\ngpt-5.2\n"))
    #expect(argsText.contains("--mode\nplan\n"))
    #expect(argsText.contains("-f\n"))

    await vm.terminate()
}

/// 承認 handler が呼ばれたかどうかを記録する Sendable なレコーダ。
/// auto-approve policy は handler を呼ばないため、テストでは `wasCalled == false` を検証する。
private final class ApprovalCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _called = false

    var wasCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _called
    }

    func markCalled() {
        lock.lock()
        _called = true
        lock.unlock()
    }
}

/// 呼ばれたら記録し accept を返す handler。auto-approve policy 下では呼ばれないはず。
private func recordingApprovalHandler(_ recorder: ApprovalCallRecorder) -> JSONRPCClient.ServerRequestHandler {
    { _ in
        recorder.markCalled()
        return .object(["decision": .string(ApprovalDecision.accept.rawValue)])
    }
}

private func assertEventuallyFileExists(_ url: URL) async throws {
    // 並列実行時の CPU 競合でも偽陰性にならないよう待ち予算を確保する
    // （検証内容＝ファイルが存在すること自体は不変。タイミング許容の調整のみ）。
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Expected file to exist at \(url.path)")
}

private func makeTemporaryDirectory(named name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeExecutableScript(_ script: String, to url: URL) throws {
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}
