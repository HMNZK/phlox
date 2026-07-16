import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-9 受け入れテスト（PM 著述・実装役は編集禁止）。
// 契約: tasks/task-9.md — @ サジェストのファイル走査を MainActor 非ブロックにする。
// (1) update は走査完了を待たずに返り、結果は後から反映される（eventual）。
// (2) 走査中は前回候補を保持する（空 flicker しない）。
// (3) 古いクエリの走査結果が新しいクエリの結果を上書きしない（世代管理）。
// 実時間 sleep に依存せず、ゲート（continuation）で provider の完了を決定論的に制御する。

/// 呼び出しごとにゲートで完了を制御できる async provider。
private final class PM3Task9GatedProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [(term: String, continuation: CheckedContinuation<[SuggestionCandidate], Never>)] = []
    private(set) var callCount = 0

    var provider: @Sendable (String) async -> [SuggestionCandidate] {
        { term in
            self.lock.withLock { self.callCount += 1 }
            return await withCheckedContinuation { continuation in
                self.lock.withLock { self.pending.append((term, continuation)) }
            }
        }
    }

    func pendingTerms() -> [String] { lock.withLock { pending.map(\.term) } }

    /// 指定 term の走査を完了させて結果を返す。
    func release(term: String, with candidates: [SuggestionCandidate]) {
        let entry = lock.withLock { () -> (String, CheckedContinuation<[SuggestionCandidate], Never>)? in
            guard let index = pending.firstIndex(where: { $0.term == term }) else { return nil }
            let e = pending.remove(at: index)
            return (e.term, e.continuation)
        }
        entry?.1.resume(returning: candidates)
    }
}

private func pm3Task9Candidate(_ title: String) -> SuggestionCandidate {
    SuggestionCandidate(title: title, insertionText: title, kind: .fileReference)
}

@Suite(.serialized)
struct PM3Task9ComposerAsyncAcceptanceTests {

    // (1)+(2): update は即返り、走査中は前回候補を保持、完了後に新候補が反映される。
    @Test @MainActor
    func slowScan_doesNotBlockUpdate_keepsPreviousCandidates_thenApplies() async throws {
        let gate = PM3Task9GatedProvider()
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider
        )

        // 1回目のクエリ "@a" — 走査完了までは候補なしでよいが、update 自体は即返る。
        controller.update(text: "@a", cursorUTF16: 2)
        try await waitUntil { gate.pendingTerms().contains("a") }
        gate.release(term: "a", with: [pm3Task9Candidate("alpha.txt")])
        try await waitUntil { controller.candidates.map(\.title) == ["alpha.txt"] }

        // 2回目のクエリ "@al" — 走査中（未 release）は前回候補 alpha.txt を保持し続ける。
        controller.update(text: "@al", cursorUTF16: 3)
        try await waitUntil { gate.pendingTerms().contains("al") }
        #expect(controller.candidates.map(\.title) == ["alpha.txt"],
                "走査中に前回候補が消えた（空 flicker）: \(controller.candidates.map(\.title))")

        gate.release(term: "al", with: [pm3Task9Candidate("alpine.md")])
        try await waitUntil { controller.candidates.map(\.title) == ["alpine.md"] }
    }

    // (3): 古いクエリの走査結果は、クエリが更新された後に完了しても採用されない。
    // coalescing モデル（PM 裁定・stage2 round2 で統一）: in-flight 中の新クエリは走査を
    // 新規起動せず pending に畳まれ、in-flight の旧結果は世代不一致で破棄される。
    @Test @MainActor
    func staleSlowResult_doesNotOverwriteNewerResult() async throws {
        let gate = PM3Task9GatedProvider()
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider
        )

        controller.update(text: "@old", cursorUTF16: 4)
        try await waitUntil { gate.pendingTerms() == ["old"] }

        // in-flight 中の新クエリは pending に畳まれる（走査は起動されない）。
        controller.update(text: "@new", cursorUTF16: 4)
        for _ in 0..<20 { await Task.yield() }
        #expect(gate.pendingTerms() == ["old"], "in-flight 中に new が provider へ到達した")

        // 古いクエリが完了しても、その結果は採用されない（クエリは @new に更新済み）。
        gate.release(term: "old", with: [pm3Task9Candidate("old-result.txt")])
        try await waitUntil { gate.pendingTerms() == ["new"] }
        #expect(!controller.candidates.map(\.title).contains("old-result.txt"),
                "古いクエリの結果が採用された: \(controller.candidates.map(\.title))")

        gate.release(term: "new", with: [pm3Task9Candidate("new-result.txt")])
        try await waitUntil { controller.candidates.map(\.title) == ["new-result.txt"] }
    }

    // トリガー解除（dismiss）後に走査が完了しても候補は復活しない。
    @Test @MainActor
    func dismissedQuery_lateResultDoesNotResurrect() async throws {
        let gate = PM3Task9GatedProvider()
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider
        )

        controller.update(text: "@x", cursorUTF16: 2)
        try await waitUntil { gate.pendingTerms().contains("x") }

        // トリガーなしテキストへ変化 → dismiss。
        controller.update(text: "plain text", cursorUTF16: 5)
        #expect(controller.candidates.isEmpty)

        gate.release(term: "x", with: [pm3Task9Candidate("ghost.txt")])
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.candidates.isEmpty, "dismiss 後に遅延結果が候補を復活させた")
    }

    // 連打の coalescing（stage2 指摘の裁定）: 走査は同時に in-flight 1本まで。
    // 走査中に届いた後続クエリは「最新の1件」だけを覚え、in-flight 完了後にその1件のみ走査する
    // （中間クエリの走査は起動しない＝キー連打で FS 走査が並行増殖しない）。
    @Test @MainActor
    func rapidUpdates_coalesceScansToInFlightOnePlusLatest() async throws {
        let gate = PM3Task9GatedProvider()
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider
        )

        controller.update(text: "@a", cursorUTF16: 2)
        try await waitUntil { gate.pendingTerms() == ["a"] }

        // in-flight（"a"）中の連打。走査は起動されない（最新 "abc" だけが記憶される）。
        controller.update(text: "@ab", cursorUTF16: 3)
        controller.update(text: "@abc", cursorUTF16: 4)
        for _ in 0..<20 { await Task.yield() }
        #expect(gate.pendingTerms() == ["a"], "in-flight 中の連打で走査が並行起動した: \(gate.pendingTerms())")

        // in-flight 完了（結果は stale として破棄）→ 最新 "abc" のみが次に走査される（"ab" は走査されない）。
        gate.release(term: "a", with: [pm3Task9Candidate("stale-a.txt")])
        try await waitUntil { gate.pendingTerms() == ["abc"] }
        #expect(gate.callCount == 2, "中間クエリ ab が走査された（coalescing されていない）: 呼び出し\(gate.callCount)回")

        gate.release(term: "abc", with: [pm3Task9Candidate("abc-result.txt")])
        try await waitUntil { controller.candidates.map(\.title) == ["abc-result.txt"] }
    }

    // coalescing の跨ターン版（stage2 round2 指摘）: in-flight 中は、別 MainActor ターンで
    // 届いたクエリでも走査を新規起動しない（最新 pending の更新のみ）。running が 0 に
    // なってから最新の1件だけを起動する。
    @Test @MainActor
    func rapidUpdatesAcrossTurns_doNotStartIntermediateScan() async throws {
        let gate = PM3Task9GatedProvider()
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider
        )

        controller.update(text: "@a", cursorUTF16: 2)
        try await waitUntil { gate.pendingTerms() == ["a"] }

        // 別ターンで中間クエリ @ab。ターンを跨いで launch Task が走る余地を与えても、
        // in-flight（"a"）中は provider("ab") に到達してはならない。
        controller.update(text: "@ab", cursorUTF16: 3)
        for _ in 0..<20 { await Task.yield() }
        #expect(gate.pendingTerms() == ["a"],
                "in-flight 中に跨ターンの中間クエリ ab が provider に到達した: \(gate.pendingTerms())")

        // さらに別ターンで @abc（pending は最新へ置き換わる）。
        controller.update(text: "@abc", cursorUTF16: 4)
        for _ in 0..<20 { await Task.yield() }
        #expect(gate.pendingTerms() == ["a"],
                "in-flight 中に跨ターンのクエリ abc が provider に到達した: \(gate.pendingTerms())")

        // in-flight 完了（stale 破棄）→ 最新 "abc" のみ走査（"ab" は走査されない）。
        gate.release(term: "a", with: [pm3Task9Candidate("stale-a.txt")])
        try await waitUntil { gate.pendingTerms() == ["abc"] }
        #expect(gate.callCount == 2, "中間クエリ ab が走査された: 呼び出し\(gate.callCount)回")

        gate.release(term: "abc", with: [pm3Task9Candidate("abc-result.txt")])
        try await waitUntil { controller.candidates.map(\.title) == ["abc-result.txt"] }
    }

    // 既存のスラッシュ経路は同期のまま（挙動同値）。
    @Test @MainActor
    func slashPath_remainsSynchronous() {
        let gate = PM3Task9GatedProvider()
        let slash = SuggestionCandidate(title: "/help", insertionText: "/help ", kind: .slashCommand)
        let controller = ComposerSuggestionController(
            slashProvider: { [slash] },
            asyncFileProvider: gate.provider
        )
        controller.update(text: "/he", cursorUTF16: 3)
        #expect(controller.candidates.map(\.title) == ["/help"], "slash 経路の同期即応答が壊れた")
        #expect(gate.callCount == 0)
    }
}
