import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

@Suite @MainActor struct MobileSkillSendTests {
    @Test func mobileSelectionUsesNativeInputAndRejectsChangedFiles() async throws {
        let project = (0..<6).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let root = project.appending(path: ".verification/mobile-skill-send-\(UUID().uuidString)")
        let directory = root.appending(path: "review")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "用途: native skill送信テスト。作成: MobileSkillSendTests。PID: \(ProcessInfo.processInfo.processIdentifier)、実行: \(ProcessInfo.processInfo.arguments.first ?? "test-runner")。出力: \(root.path)".write(to: root.appending(path: "owner.txt"), atomically: true, encoding: .utf8)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { Issue.record("fixture cleanup failed: \(error)") }
        }
        let path = directory.appending(path: "SKILL.md")
        try "Review".write(to: path, atomically: true, encoding: .utf8)
        let client = MobileSkillClient(path: path.path)
        let vm = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: root.path)
        do {
            let candidate = try #require(try await vm.mobileSkills().first)
            let selection = AgentSkillSelection(name: candidate.name, path: candidate.path, runtimeFingerprint: candidate.runtimeFingerprint)
            await #expect(throws: ChatSessionViewModel.ControlSkillError.self) {
                try await vm.sendTextWithControlSkill("inspect", submit: true, images: [], skill: selection)
            }
            let forged = AgentSkillSelection(name: "missing", path: candidate.path, runtimeFingerprint: candidate.runtimeFingerprint)
            await #expect(throws: ChatSessionViewModel.ControlSkillError.self) {
                try await vm.sendTextWithControlSkill("$missing inspect", submit: true, images: [], skill: forged)
            }
            #expect(await client.sent.isEmpty)
            try await vm.sendTextWithControlSkill("$review inspect", submit: true, images: [], skill: selection)
            let sent = await client.sent
            #expect(sent.count == 1)
            #expect(sent.first?.contains(.skill(name: "review", path: path.path)) == true)
            #expect(sent.first?.contains(.text("inspect")) == true)
            #expect(vm.codexSkillSelectionState?.selectedSkill == nil)
            try "Changed".write(to: path, atomically: true, encoding: .utf8)
            await #expect(throws: ChatSessionViewModel.ControlSkillError.self) {
                try await vm.sendTextWithControlSkill("$review inspect", submit: true, images: [], skill: selection)
            }
            #expect(await client.sent.count == 1)

            let state = try #require(vm.codexSkillSelectionState)
            #expect(state.select(try #require(state.skills.first)))
            try "Changed again".write(to: path, atomically: true, encoding: .utf8)
            let refreshed = try #require(try await vm.mobileSkills().first)
            let refreshedSelection = AgentSkillSelection(name: refreshed.name, path: refreshed.path,
                runtimeFingerprint: refreshed.runtimeFingerprint)
            let desktopSelection = state.runtimeSelectionIdentity
            #expect(state.requiresReselection)
            try await vm.sendTextWithControlSkill("$review inspect", submit: true, images: [], skill: refreshedSelection)
            #expect(state.runtimeSelectionIdentity == desktopSelection)
            #expect(state.requiresReselection)

            await client.onSend {
                #expect(state.select(name: "other", path: path.path))
            }
            try await vm.sendTextWithControlSkill("$review inspect", submit: true, images: [], skill: refreshedSelection)
            #expect(state.selectedSkill?.name == "other")
            #expect(!state.requiresReselection)
            #expect(await client.sent.count == 3)

            let runtimeClient = MobileSkillClient(path: path.path)
            let owner = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.codex), client: runtimeClient,
                approvalBroker: ChatApprovalBroker(), workingDirectory: root.path)
            do {
                _ = try await owner.mobileSkills()
                let ownerState = try #require(owner.codexSkillSelectionState)
                #expect(ownerState.select(name: "other", path: path.path))
                let projection = ChatSessionViewModel(projection: owner.makeRuntimeSnapshot()) { executionID, command in
                    let wire = try JSONDecoder().decode(SessionRuntimeSessionCommand.self, from: JSONEncoder().encode(command))
                    guard case .sendControlSkill = wire else { throw SessionRuntimeProjectionError.unsupportedCommand }
                    return try await owner.performRuntimeCommand(wire, expectedExecutionID: executionID)
                }
                let projectedState = try #require(projection.codexSkillSelectionState)
                #expect(projectedState.select(name: "other", path: path.path))
                var sends = runtimeClient.sends.makeAsyncIterator()
                let watchdog = Task {
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { return }
                    runtimeClient.finishSends()
                }
                defer { watchdog.cancel() }
                try await projection.sendTextWithControlSkill("$review inspect", submit: true, images: [], skill: refreshedSelection)
                #expect(await sends.next() != nil)
                let clock = ContinuousClock()
                let deadline = clock.now + .seconds(2)
                while owner.inFlightText != nil, clock.now < deadline { await Task.yield() }
                #expect(owner.inFlightText == nil)
                #expect(await runtimeClient.sent.first?.contains(.skill(name: "review", path: path.path)) == true)
                #expect(ownerState.selectedSkill?.name == "other")
                #expect(projectedState.selectedSkill?.name == "other")
            } catch {
                await owner.terminate()
                throw error
            }
            await owner.terminate()
        } catch {
            await vm.terminate()
            throw error
        }
        await vm.terminate()
    }
}

private final class MobileSkillClient: StructuredAgentClient, CodexSkillSelectionClient, CodexNativeSkillInputSending, Sendable {
    let events = AsyncStream<NormalizedChatEvent> { $0.finish() }
    let skillEvents = AsyncStream<ThreadEvent> { $0.finish() }
    let path: String
    let sends: AsyncStream<Void>
    private let sendContinuation: AsyncStream<Void>.Continuation
    private actor Recorder {
        var inputs: [[UserInput]] = []
        var onSend: (@MainActor @Sendable () -> Void)?
        func record(_ input: [UserInput]) { inputs.append(input) }
        func setOnSend(_ action: @escaping @MainActor @Sendable () -> Void) { onSend = action }
    }
    private let recorder = Recorder()
    init(path: String) {
        self.path = path
        let stream = AsyncStream<Void>.makeStream()
        sends = stream.stream
        sendContinuation = stream.continuation
    }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws { Issue.record("native skill was dropped") }
    func turnStartNative(_ input: [UserInput]) async throws {
        await recorder.record(input)
        let action = await recorder.onSend
        await action?()
        sendContinuation.yield(())
    }
    func onSend(_ action: @escaping @MainActor @Sendable () -> Void) async { await recorder.setOnSend(action) }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { finishSends() }
    func finishSends() { sendContinuation.finish() }
    func skillsList(_ params: SkillsListParams) async throws -> SkillsListResponse {
        SkillsListResponse(data: [SkillsListEntry(cwd: params.cwds?.first ?? "", errors: [], skills: [
            SkillMetadata(description: "Review", enabled: true, name: "review", path: path, scope: .user),
            SkillMetadata(description: "Other", enabled: true, name: "other", path: path, scope: .user)
        ])])
    }
    var sent: [[UserInput]] { get async { await recorder.inputs } }
}
