import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// @ サジェストのファイル走査は MainActor を塞がない（update は走査完了を待たずに返り、結果は後から反映される）。
//   (1) warm キャッシュ hit は同期 fast-path（背景走査を起動しない・isScanning は上がらない）
//   (2) miss は背景走査（前回候補を保持し isScanning=true → 完了で反映・isScanning=false）
//   (3) コールドバースト連打は先頭のみ起動し、以降は最新 pending へ畳む（provider は 2 回）
//   (3b) 走行中は別ターンのクエリも provider へ到達させない（running 中は新規起動しない）
//   (4) dismiss は走査中でも即クリア＋世代を進め、遅延結果を無効化し isScanning=false
//   (5) スラッシュ経路への切替も世代を進め、遅延ファイル結果を無効化する。スラッシュ経路は同期のまま
// provider の完了は continuation ゲートで決定論的に制御する（実時間 sleep 非依存）。

/// 呼び出しごとにゲートで完了を制御できる async provider。
private final class GatedProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [(term: String, cont: CheckedContinuation<[SuggestionCandidate], Never>)] = []
    private(set) var callCount = 0

    var provider: @Sendable (String) async -> [SuggestionCandidate] {
        { term in
            self.lock.withLock { self.callCount += 1 }
            return await withCheckedContinuation { cont in
                self.lock.withLock { self.pending.append((term, cont)) }
            }
        }
    }

    func pendingTerms() -> [String] { lock.withLock { pending.map(\.term) } }

    func release(term: String, with candidates: [SuggestionCandidate]) {
        let cont = lock.withLock { () -> CheckedContinuation<[SuggestionCandidate], Never>? in
            guard let index = pending.firstIndex(where: { $0.term == term }) else { return nil }
            return pending.remove(at: index).cont
        }
        cont?.resume(returning: candidates)
    }
}

private func fileCandidate(_ title: String) -> SuggestionCandidate {
    SuggestionCandidate(title: title, insertionText: "@\(title)", kind: .fileReference)
}

@Suite("Composer async @ suggestions", .serialized)
struct ComposerAsyncSuggestionTests {

    // warm キャッシュ hit: 同期即応答。背景走査（async provider）を一切呼ばない。
    @Test @MainActor
    func warmCacheHit_appliesSynchronously_withoutBackgroundScan() {
        let gate = GatedProvider()
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider,
            cachedFileProvider: { term in term == "w" ? [fileCandidate("warm.txt")] : nil }
        )

        controller.update(text: "@w", cursorUTF16: 2)

        // yield/await を挟まずに（＝同期で）候補が入っていること。
        #expect(controller.candidates.map(\.title) == ["warm.txt"])
        #expect(controller.isScanning == false)
        #expect(gate.callCount == 0, "warm hit で背景走査が起動された")
    }

    // miss: 背景走査。走査中は前回（warm）候補を保持、isScanning=true、完了で反映。
    @Test @MainActor
    func cacheMiss_scansInBackground_keepsPreviousCandidates_thenApplies() async throws {
        let gate = GatedProvider()
        let warmTerms: Set<String> = ["seed"]
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider,
            cachedFileProvider: { term in warmTerms.contains(term) ? [fileCandidate("seed.txt")] : nil }
        )

        // warm seed で前回候補を同期で用意。
        controller.update(text: "@seed", cursorUTF16: 5)
        #expect(controller.candidates.map(\.title) == ["seed.txt"])
        #expect(gate.callCount == 0)

        // miss クエリ → 背景走査。前回候補 seed.txt を保持し isScanning=true。
        controller.update(text: "@miss", cursorUTF16: 5)
        try await waitUntil { gate.pendingTerms().contains("miss") }
        #expect(controller.candidates.map(\.title) == ["seed.txt"], "走査中に候補が消えた（空 flicker）")
        #expect(controller.isScanning == true)

        gate.release(term: "miss", with: [fileCandidate("miss.txt")])
        try await waitUntil { controller.candidates.map(\.title) == ["miss.txt"] }
        #expect(controller.isScanning == false)
    }

    // コールドバースト: in-flight 開始前の連打は「先頭だけ起動」し、以降は最新 pending へ畳む。
    // 先頭完了（stale 破棄）→ 最新 pending のみ起動（中間は走らない・provider は 2 回だけ）。
    // stage2 round2 の裁定「running 中は新規起動しない」を同一ターンで固定する。
    @Test @MainActor
    func coldBurst_startsFirstQuery_coalescesRestToLatestPending() async throws {
        let gate = GatedProvider()
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider // cachedFileProvider 無し → 常に背景走査
        )

        controller.update(text: "@a", cursorUTF16: 2)
        controller.update(text: "@ab", cursorUTF16: 3)
        controller.update(text: "@abc", cursorUTF16: 4)
        try await waitUntil { gate.pendingTerms() == ["a"] }
        for _ in 0..<20 { await Task.yield() }
        #expect(gate.pendingTerms() == ["a"], "先頭以外が並行起動した: \(gate.pendingTerms())")
        #expect(gate.callCount == 1)

        // 先頭 "a" 完了（世代不一致で破棄）→ 最新 pending "abc" のみ起動（中間 "ab" は起動しない）。
        gate.release(term: "a", with: [fileCandidate("a.txt")])
        try await waitUntil { gate.pendingTerms() == ["abc"] }
        #expect(gate.callCount == 2, "中間 ab が走査された（coalescing されていない）: \(gate.callCount)回")
        #expect(!controller.candidates.map(\.title).contains("a.txt"), "stale な先頭結果が採用された")

        gate.release(term: "abc", with: [fileCandidate("abc.txt")])
        try await waitUntil { controller.candidates.map(\.title) == ["abc.txt"] }
        #expect(controller.isScanning == false)
    }

    // 走行中の走査がある間は、別ターンで届いたクエリも provider に到達しない（pending へ）。
    // 完了後に最新 pending のみ 1 本起動する。これが round2 HIGH の本丸
    // （非協調 FS 走査は cancel で止まらないため、そもそも起動しないことで増殖を断つ）。
    @Test @MainActor
    func runningScan_blocksNewLaunch_untilCompletion() async throws {
        let gate = GatedProvider()
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider
        )

        controller.update(text: "@x", cursorUTF16: 2)
        try await waitUntil { gate.pendingTerms() == ["x"] }   // "x" 走行中（provider 到達）

        // 走行中に届いた別ターンのクエリは provider へ到達しない（最新 pending へ畳まれる）。
        controller.update(text: "@y", cursorUTF16: 2)
        for _ in 0..<20 { await Task.yield() }
        #expect(gate.pendingTerms() == ["x"], "走行中に y が並行起動した: \(gate.pendingTerms())")
        #expect(controller.isScanning == true)

        // "x" 完了（世代不一致で破棄）→ pending "y" のみ起動。
        gate.release(term: "x", with: [fileCandidate("x.txt")])
        try await waitUntil { gate.pendingTerms() == ["y"] }
        #expect(gate.callCount == 2)
        #expect(!controller.candidates.map(\.title).contains("x.txt"), "stale な走行中結果が採用された")

        gate.release(term: "y", with: [fileCandidate("y.txt")])
        try await waitUntil { controller.candidates.map(\.title) == ["y.txt"] }
        #expect(controller.isScanning == false)
    }

    // dismiss: 走査中でも即クリア＋世代を進め、遅延結果を無効化。
    @Test @MainActor
    func dismissDuringScan_stopsScanning_andLateResultDiscarded() async throws {
        let gate = GatedProvider()
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider
        )

        controller.update(text: "@q", cursorUTF16: 2)
        try await waitUntil { gate.pendingTerms().contains("q") }
        #expect(controller.isScanning == true)

        controller.dismiss()
        #expect(controller.candidates.isEmpty)
        #expect(controller.isScanning == false)

        gate.release(term: "q", with: [fileCandidate("late.txt")])
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.candidates.isEmpty, "dismiss 後に遅延結果が候補を復活させた")
        #expect(controller.isScanning == false)
    }

    // スラッシュ経路への切替も世代を進め、遅延ファイル結果を無効化する。
    @Test @MainActor
    func slashAfterPendingFileScan_discardsLateFileResult() async throws {
        let gate = GatedProvider()
        let slash = SuggestionCandidate(title: "/help", insertionText: "/help", kind: .slashCommand)
        let controller = ComposerSuggestionController(
            slashProvider: { [slash] },
            asyncFileProvider: gate.provider
        )

        controller.update(text: "@f", cursorUTF16: 2)
        try await waitUntil { gate.pendingTerms().contains("f") }
        #expect(controller.isScanning == true)

        // スラッシュへ切替（同期）。走査は無効化され isScanning=false。
        controller.update(text: "/h", cursorUTF16: 2)
        #expect(controller.candidates.map(\.title) == ["/help"])
        #expect(controller.isScanning == false)

        gate.release(term: "f", with: [fileCandidate("file.txt")])
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.candidates.map(\.title) == ["/help"], "遅延ファイル結果がスラッシュ候補を上書きした")
        #expect(controller.isScanning == false)
    }

    // トリガー解除（dismiss）後に走査が完了しても候補は復活しない。
    @Test @MainActor
    func dismissedQuery_lateResultDoesNotResurrect() async throws {
        let gate = GatedProvider()
        let controller = ComposerSuggestionController(
            slashProvider: { [] },
            asyncFileProvider: gate.provider
        )

        controller.update(text: "@x", cursorUTF16: 2)
        try await waitUntil { gate.pendingTerms().contains("x") }

        // トリガーなしテキストへ変化 → dismiss。
        controller.update(text: "plain text", cursorUTF16: 5)
        #expect(controller.candidates.isEmpty)

        gate.release(term: "x", with: [fileCandidate("ghost.txt")])
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.candidates.isEmpty, "dismiss 後に遅延結果が候補を復活させた")
    }

    // coalescing の跨ターン版（stage2 round2 指摘）: in-flight 中は、別 MainActor ターンで
    // 届いたクエリでも走査を新規起動しない（最新 pending の更新のみ）。running が 0 に
    // なってから最新の1件だけを起動する。
    @Test @MainActor
    func rapidUpdatesAcrossTurns_doNotStartIntermediateScan() async throws {
        let gate = GatedProvider()
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
        gate.release(term: "a", with: [fileCandidate("stale-a.txt")])
        try await waitUntil { gate.pendingTerms() == ["abc"] }
        #expect(gate.callCount == 2, "中間クエリ ab が走査された: 呼び出し\(gate.callCount)回")

        gate.release(term: "abc", with: [fileCandidate("abc-result.txt")])
        try await waitUntil { controller.candidates.map(\.title) == ["abc-result.txt"] }
    }

    // 既存のスラッシュ経路は同期のまま（挙動同値）。
    @Test @MainActor
    func slashPath_remainsSynchronous() {
        let gate = GatedProvider()
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
