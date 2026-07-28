import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

// task-4 白箱テスト（実装役著）。ChatSessionViewModel と永続ストアの配線を覆う:
//   - 生成時に1回だけストアを読み、seedSlashCommands に入れる
//   - .availableCommandsUpdated でストアへ記録する（他イベントでは触らない）

private struct DefaultsSandboxUnavailable: Error {}

/// テスト専用の UserDefaults suite。`UserDefaults.standard` を汚さない。
private final class DefaultsSandbox {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        let name = "phlox.tests.seedWiring.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: name) else { throw DefaultsSandboxUnavailable() }
        suiteName = name
        defaults = suite
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}

private final class SeedWiringFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_500_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

private let workspace = "/tmp/phlox-seed-wiring-test"

/// provider が受け取った種一覧を控える器（同期・非同期どちらの provider からも書く）。
private final class SeedProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String]??

    var last: [String]? {
        lock.lock()
        defer { lock.unlock() }
        return value ?? nil
    }

    func recordSynchronously(_ seed: [String]?) {
        lock.lock()
        value = .some(seed)
        lock.unlock()
    }

    func record(_ seed: [String]?) async {
        recordSynchronously(seed)
    }
}

@MainActor
private func makeViewModel(
    store: AvailableCommandsStore,
    agentRef: AgentRef = .builtin(.claudeCode)
) -> (ChatSessionViewModel, SeedWiringFakeClient) {
    let client = SeedWiringFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: agentRef,
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: workspace,
        availableCommandsStore: store
    )
    return (vm, client)
}

private func makeCollisionWorkspace(skillDescription: String) throws -> URL {
    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-seed-collision-\(UUID().uuidString)", isDirectory: true)
    let skillDirectory = workspace.appending(path: ".claude/skills/collision", directoryHint: .isDirectory)
    let commandDirectory = workspace.appending(path: ".claude/commands", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: commandDirectory, withIntermediateDirectories: true)
    try """
    ---
    name: collision
    description: \(skillDescription)
    ---

    本文
    """.write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
    try "本文".write(to: commandDirectory.appending(path: "collision.md"), atomically: true, encoding: .utf8)
    try "本文".write(to: commandDirectory.appending(path: "command-only.md"), atomically: true, encoding: .utf8)
    return workspace
}

@Suite("白箱: 種一覧の subtitle 優先順（task-4 レビュー指摘）")
struct SeedCommandsSubtitlePrecedenceTests {

    @Test("同名の skill と custom command では、seed 経由なら skill の説明を優先する")
    func skillSubtitleWinsOverCustomCommandForSeed() throws {
        let workspace = try makeCollisionWorkspace(skillDescription: "スキル説明")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["collision"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let candidate = try #require(candidates.first { $0.title == "/collision" })
        #expect(candidate.subtitle == "スキル説明")
    }

    @Test("seed に含まれない名前の衝突では、従来どおり Custom command が残る")
    func customCommandStillWinsForNonSeededNames() throws {
        let workspace = try makeCollisionWorkspace(skillDescription: "スキル説明")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["unrelated-seed"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let candidate = try #require(candidates.first { $0.title == "/collision" })
        #expect(candidate.subtitle == "Custom command", "seed 外の衝突は既存挙動（カスタムコマンド先勝ち）のまま")
        #expect(candidates.contains { $0.title == "/command-only" }, "seed に無いカスタムコマンドも残ること")
        #expect(candidates.contains { $0.title == "/unrelated-seed" })
    }
}

@Suite("白箱: 種一覧の配線（task-4）")
struct SeedCommandsWiringWhiteboxTests {

    @Test @MainActor
    func seedIsReadFromStoreAtInit() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)
        store.record(
            agentRef: .builtin(.claudeCode),
            workingDirectory: workspace,
            commands: ["ultrareview", "deep-research"]
        )

        let (vm, _) = makeViewModel(store: store)

        #expect(vm.seedSlashCommands == ["ultrareview", "deep-research"])
        #expect(vm.availableSlashCommands == nil, "seed は受領済み一覧の代わりにはしないこと")
    }

    @Test @MainActor
    func seedIsNilWhenStoreHasNothing() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)

        let (vm, _) = makeViewModel(store: store)

        #expect(vm.seedSlashCommands == nil)
    }

    @Test @MainActor
    func seedIsScopedToAgentAndWorkingDirectory() throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)
        store.record(
            agentRef: .builtin(.claudeCode),
            workingDirectory: workspace,
            commands: ["ultrareview"]
        )

        let (vm, _) = makeViewModel(store: store, agentRef: .builtin(.codex))

        #expect(vm.seedSlashCommands == nil, "別エージェントの種を読まないこと")
    }

    @Test @MainActor
    func availableCommandsUpdatedIsRecordedIntoStore() async throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)
        let (vm, client) = makeViewModel(store: store)

        client.yield(.availableCommandsUpdated(commands: ["clear", "ultrareview"]))
        try await waitUntil { vm.availableSlashCommands != nil }

        #expect(
            store.commands(agentRef: .builtin(.claudeCode), workingDirectory: workspace)
                == ["clear", "ultrareview"],
            "次回セッションの種として永続化すること"
        )
    }

    @Test @MainActor
    func seedStaysAtInitValueAfterListArrives() async throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)
        store.record(
            agentRef: .builtin(.claudeCode),
            workingDirectory: workspace,
            commands: ["seeded-at-init"]
        )
        let (vm, client) = makeViewModel(store: store)

        client.yield(.availableCommandsUpdated(commands: ["clear"]))
        try await waitUntil { vm.availableSlashCommands != nil }

        #expect(vm.seedSlashCommands == ["seeded-at-init"], "seed は生成時の1回読みで固定すること")
    }

    @Test @MainActor
    func controllerPassesSeedToSlashProvider() async throws {
        let received = SeedProbe()
        let controller = ComposerSuggestionController(
            seedAwareAsyncSlashProvider: { _, _, seed in
                await received.record(seed)
                return []
            },
            seedAwareCachedSlashProvider: { _, _, seed in
                received.recordSynchronously(seed)
                return [SuggestionCandidate(title: "/seeded", insertionText: "/seeded", subtitle: nil, kind: .slashCommand)]
            },
            asyncFileProvider: { _ in [] },
            cachedFileProvider: { _ in nil }
        )
        controller.seedSlashCommands = ["seeded"]

        controller.update(text: "/se", cursorUTF16: 3)

        #expect(received.last == ["seeded"], "controller の種一覧を provider へ渡すこと")
        #expect(controller.candidates.map(\.title) == ["/seeded"])
    }

    /// VM（永続ストア）→ controller → 候補までを production 経路で通す。
    @Test @MainActor
    func viewModelSeedReachesProductionCandidates() async throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-seed-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)
        let seedName = "seeded-\(UUID().uuidString.prefix(8))"
        store.record(
            agentRef: .builtin(.claudeCode),
            workingDirectory: workspaceURL.path,
            commands: [String(seedName)]
        )
        let client = SeedWiringFakeClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: workspaceURL.path,
            availableCommandsStore: store
        )

        let controller = ComposerSuggestionController.production(workingDirectory: workspaceURL.path)
        // View（ChatComposer / GridChatColumn）の onAppear 配線と同じことをする。
        controller.availableSlashCommands = vm.availableSlashCommands
        controller.seedSlashCommands = vm.seedSlashCommands

        controller.update(text: "/seeded", cursorUTF16: 7)
        try await waitUntil { controller.candidates.contains { $0.title == "/\(seedName)" } }

        #expect(
            controller.candidates.contains { $0.title == "/\(seedName)" },
            "1通も送る前に、前回セッションの一覧から候補が出ること"
        )
    }

    @Test @MainActor
    func unrelatedEventsDoNotTouchTheStore() async throws {
        let sandbox = try DefaultsSandbox()
        let store = AvailableCommandsStore(defaults: sandbox.defaults)
        store.record(
            agentRef: .builtin(.claudeCode),
            workingDirectory: workspace,
            commands: ["previously-recorded"]
        )
        let (vm, client) = makeViewModel(store: store)

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }

        #expect(
            store.commands(agentRef: .builtin(.claudeCode), workingDirectory: workspace)
                == ["previously-recorded"],
            "無関係なイベントで記録を消さないこと"
        )
    }
}
