import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class AsyncSlashWhiteboxGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [(term: String, continuation: CheckedContinuation<[SuggestionCandidate], Never>)] = []
    private var calls = 0

    var provider: @Sendable (String) async -> [SuggestionCandidate] {
        { term in
            self.lock.withLock { self.calls += 1 }
            return await withCheckedContinuation { continuation in
                self.lock.withLock { self.pending.append((term, continuation)) }
            }
        }
    }

    var callCount: Int { lock.withLock { calls } }

    func pendingTerms() -> [String] {
        lock.withLock { pending.map(\.term) }
    }

    func release(term: String, with candidates: [SuggestionCandidate]) {
        let continuation = lock.withLock { () -> CheckedContinuation<[SuggestionCandidate], Never>? in
            guard let index = pending.firstIndex(where: { $0.term == term }) else { return nil }
            return pending.remove(at: index).continuation
        }
        continuation?.resume(returning: candidates)
    }
}

private func asyncSlashWhiteboxSlash(_ title: String) -> SuggestionCandidate {
    SuggestionCandidate(title: title, insertionText: title, kind: .slashCommand)
}

private func asyncSlashWhiteboxFile(_ title: String) -> SuggestionCandidate {
    SuggestionCandidate(title: title, insertionText: "@\(title)", kind: .fileReference)
}

@Suite(.serialized)
struct AsyncSlashWhiteboxTests {
    @Test @MainActor
    func warmSlashHitUsesCacheWithoutStartingScan() {
        let slashGate = AsyncSlashWhiteboxGate()
        let controller = ComposerSuggestionController(
            asyncSlashProvider: slashGate.provider,
            cachedSlashProvider: { term in
                term == "he" ? [asyncSlashWhiteboxSlash("/help")] : nil
            },
            asyncFileProvider: { _ in [] },
            cachedFileProvider: { _ in nil }
        )

        controller.update(text: "/he", cursorUTF16: 3)

        #expect(controller.candidates.map(\.title) == ["/help"])
        #expect(controller.isScanning == false)
        #expect(slashGate.callCount == 0)
    }

    @Test @MainActor
    func slashMissKeepsWarmCandidatesUntilBackgroundResultArrives() async throws {
        let slashGate = AsyncSlashWhiteboxGate()
        let controller = ComposerSuggestionController(
            asyncSlashProvider: slashGate.provider,
            cachedSlashProvider: { term in
                term == "seed" ? [asyncSlashWhiteboxSlash("/seed")] : nil
            },
            asyncFileProvider: { _ in [] },
            cachedFileProvider: { _ in nil }
        )

        controller.update(text: "/seed", cursorUTF16: 5)
        controller.update(text: "/miss", cursorUTF16: 5)
        try await waitUntil { slashGate.pendingTerms() == ["miss"] }

        #expect(controller.candidates.map(\.title) == ["/seed"])
        #expect(controller.isScanning == true)

        slashGate.release(term: "miss", with: [asyncSlashWhiteboxSlash("/mission")])
        try await waitUntil { controller.candidates.map(\.title) == ["/mission"] }
        #expect(controller.isScanning == false)
    }

    @Test @MainActor
    func slashBurstRunsOnlyFirstAndLatestQueries() async throws {
        let slashGate = AsyncSlashWhiteboxGate()
        let controller = ComposerSuggestionController(
            asyncSlashProvider: slashGate.provider,
            cachedSlashProvider: { _ in nil },
            asyncFileProvider: { _ in [] },
            cachedFileProvider: { _ in nil }
        )

        controller.update(text: "/a", cursorUTF16: 2)
        controller.update(text: "/ab", cursorUTF16: 3)
        controller.update(text: "/abc", cursorUTF16: 4)
        try await waitUntil { slashGate.pendingTerms() == ["a"] }
        #expect(slashGate.callCount == 1)

        slashGate.release(term: "a", with: [asyncSlashWhiteboxSlash("/stale")])
        try await waitUntil { slashGate.pendingTerms() == ["abc"] }
        #expect(slashGate.callCount == 2)
        #expect(controller.candidates.isEmpty)

        slashGate.release(term: "abc", with: [asyncSlashWhiteboxSlash("/abc")])
        try await waitUntil { controller.candidates.map(\.title) == ["/abc"] }
    }

    @Test @MainActor
    func coldKindSwitchSharesGenerationAndLaunchesLatestProviderOnly() async throws {
        let slashGate = AsyncSlashWhiteboxGate()
        let fileGate = AsyncSlashWhiteboxGate()
        let controller = ComposerSuggestionController(
            asyncSlashProvider: slashGate.provider,
            cachedSlashProvider: { _ in nil },
            asyncFileProvider: fileGate.provider,
            cachedFileProvider: { _ in nil }
        )

        controller.update(text: "/s", cursorUTF16: 2)
        try await waitUntil { slashGate.pendingTerms() == ["s"] }

        controller.update(text: "@f", cursorUTF16: 2)
        for _ in 0..<20 { await Task.yield() }
        #expect(fileGate.callCount == 0)

        slashGate.release(term: "s", with: [asyncSlashWhiteboxSlash("/stale")])
        try await waitUntil { fileGate.pendingTerms() == ["f"] }
        #expect(controller.candidates.isEmpty)

        fileGate.release(term: "f", with: [asyncSlashWhiteboxFile("fresh.txt")])
        try await waitUntil { controller.candidates.map(\.title) == ["fresh.txt"] }
        #expect(controller.isScanning == false)
    }
}
