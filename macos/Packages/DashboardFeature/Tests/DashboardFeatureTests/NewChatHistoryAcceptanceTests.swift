import Foundation
import Testing
import SessionFeature
@testable import DashboardFeature

private actor FakeHistoryLoader {
    private var attempts = 0
    private let entry: ClaudeSessionHistoryEntry

    init(entry: ClaudeSessionHistoryEntry) {
        self.entry = entry
    }

    func load() async throws -> [ClaudeSessionHistoryEntry] {
        attempts += 1
        try await Task.sleep(for: .milliseconds(20))
        switch attempts {
        case 1: throw NSError(domain: "FakeHistory", code: 1)
        case 2: return []
        default: return [entry]
        }
    }
}

@Test @MainActor
func AC18_newChatHistoryDistinguishesLoadingEmptyFailureAndRetry() async throws {
    let model = NewChatHistoryPopoverModel()
    let entry = ClaudeSessionHistoryEntry(
        sessionID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        preview: "履歴の依頼",
        firstUserAt: nil,
        lastModified: Date(timeIntervalSince1970: 1_800),
        gitBranch: nil,
        fileURL: URL(fileURLWithPath: "/tmp/history.jsonl"),
        sourceWorkingDirectory: "/tmp/project"
    )
    let fake = FakeHistoryLoader(entry: entry)
    let loader: @Sendable () async throws -> [ClaudeSessionHistoryEntry] = {
        try await fake.load()
    }

    let firstLoad = Task { await model.load(from: loader) }
    for _ in 0..<100 where model.state != .loading([]) {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(model.state == .loading([]))
    await firstLoad.value
    #expect(model.state == .failed)

    await model.load(from: loader)
    #expect(model.state == .empty)
    await model.load(from: loader)
    #expect(model.state == .entries([entry]))
}
