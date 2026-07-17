import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// task-1 受け入れテスト（PM 著述・実装役は編集禁止）。
// 契約: tasks/task-1.md — スラッシュサジェスト算出を MainActor 非ブロックにする
// （task-9 が @ ファイル参照に施した非同期パターンをスラッシュへ横展開）。
//
// 固定する契約:
//  (1) warm キャッシュ hit（cachedSlashProvider 非 nil）は同期即応答。asyncSlashProvider を呼ばない・isScanning を上げない。
//  (2) miss は背景走査。update は走査完了を await せず即返り、走査中は前回候補を保持、完了で反映。
//  (3) 連打（コールドバースト）は in-flight 1本＋最新 pending へ畳む（中間クエリは走らせない）。
//  (4) slash⇄file の kind 切替でも共有世代が正しく前進し、旧 kind の遅延走査結果が新 kind 候補を上書きしない。
//  (5) dismiss 後に遅延走査結果が候補を復活させない。
//
// provider の完了はゲート（continuation）で決定論的に制御する（実時間 sleep 非依存）。
// 実装役へ: これらのアサーションは変更禁止。ハーネス欠陥を見つけた場合のみ PM 承認を得てハーネス部分を修理する。

/// 呼び出しごとにゲートで完了を制御できる async provider（本ファイル専用）。
private final class SlashGatedProvider: @unchecked Sendable {
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

    func release(term: String, with candidates: [SuggestionCandidate]) {
        let cont = lock.withLock { () -> CheckedContinuation<[SuggestionCandidate], Never>? in
            guard let index = pending.firstIndex(where: { $0.term == term }) else { return nil }
            return pending.remove(at: index).continuation
        }
        cont?.resume(returning: candidates)
    }
}

private func slashCand(_ title: String) -> SuggestionCandidate {
    SuggestionCandidate(title: title, insertionText: title, kind: .slashCommand)
}

private func fileCand(_ title: String) -> SuggestionCandidate {
    SuggestionCandidate(title: title, insertionText: "@\(title)", kind: .fileReference)
}

@Suite(.serialized)
struct AsyncSlashSuggestionAcceptanceTests {

    // (1) warm hit: 同期即応答。背景走査（asyncSlashProvider）を一切呼ばない・isScanning は上がらない。
    @Test @MainActor
    func slashWarmCacheHit_appliesSynchronously_withoutBackgroundScan() {
        let slashGate = SlashGatedProvider()
        let controller = ComposerSuggestionController(
            asyncSlashProvider: slashGate.provider,
            cachedSlashProvider: { term in term == "he" ? [slashCand("/help")] : nil },
            asyncFileProvider: { _ in [] },
            cachedFileProvider: { _ in nil }
        )

        controller.update(text: "/he", cursorUTF16: 3)

        #expect(controller.candidates.map(\.title) == ["/help"], "slash warm hit の同期即応答が壊れた")
        #expect(controller.isScanning == false)
        #expect(slashGate.callCount == 0, "warm hit で slash 背景走査が起動された")
    }

    // (2) miss: 背景走査。update は即返り、走査中は前回候補を保持、完了で反映。
    @Test @MainActor
    func slashCacheMiss_scansInBackground_keepsPreviousCandidates_thenApplies() async throws {
        let slashGate = SlashGatedProvider()
        let controller = ComposerSuggestionController(
            asyncSlashProvider: slashGate.provider,
            cachedSlashProvider: { term in term == "seed" ? [slashCand("/seed")] : nil },
            asyncFileProvider: { _ in [] },
            cachedFileProvider: { _ in nil }
        )

        // warm seed で前回候補を同期用意。
        controller.update(text: "/seed", cursorUTF16: 5)
        #expect(controller.candidates.map(\.title) == ["/seed"])
        #expect(slashGate.callCount == 0)

        // miss クエリ → 背景走査。前回候補 /seed を保持し isScanning=true。
        controller.update(text: "/miss", cursorUTF16: 5)
        try await waitUntil { slashGate.pendingTerms().contains("miss") }
        #expect(controller.candidates.map(\.title) == ["/seed"], "走査中に候補が消えた（空 flicker）")
        #expect(controller.isScanning == true)

        slashGate.release(term: "miss", with: [slashCand("/mission")])
        try await waitUntil { controller.candidates.map(\.title) == ["/mission"] }
        #expect(controller.isScanning == false)
    }

    // (3) コールドバースト連打: 先頭のみ起動、以降は最新 pending へ畳む（中間は走らない・provider は2回）。
    @Test @MainActor
    func slashColdBurst_startsFirstQuery_coalescesRestToLatestPending() async throws {
        let slashGate = SlashGatedProvider()
        let controller = ComposerSuggestionController(
            asyncSlashProvider: slashGate.provider,
            cachedSlashProvider: { _ in nil }, // 常に miss → 背景走査
            asyncFileProvider: { _ in [] },
            cachedFileProvider: { _ in nil }
        )

        controller.update(text: "/a", cursorUTF16: 2)
        controller.update(text: "/ab", cursorUTF16: 3)
        controller.update(text: "/abc", cursorUTF16: 4)
        try await waitUntil { slashGate.pendingTerms() == ["a"] }
        for _ in 0..<20 { await Task.yield() }
        #expect(slashGate.pendingTerms() == ["a"], "先頭以外が並行起動した: \(slashGate.pendingTerms())")
        #expect(slashGate.callCount == 1)

        slashGate.release(term: "a", with: [slashCand("/a-stale")])
        try await waitUntil { slashGate.pendingTerms() == ["abc"] }
        #expect(slashGate.callCount == 2, "中間 ab が走査された（coalescing 不備）: \(slashGate.callCount)回")
        #expect(!controller.candidates.map(\.title).contains("/a-stale"), "stale な先頭結果が採用された")

        slashGate.release(term: "abc", with: [slashCand("/abc-done")])
        try await waitUntil { controller.candidates.map(\.title) == ["/abc-done"] }
        #expect(controller.isScanning == false)
    }

    // (4) kind 切替: file warm 同期反映が、in-flight の slash 走査を無効化する（遅延 slash 結果を破棄）。
    @Test @MainActor
    func fileWarmHit_invalidatesPendingSlashScan() async throws {
        let slashGate = SlashGatedProvider()
        let controller = ComposerSuggestionController(
            asyncSlashProvider: slashGate.provider,
            cachedSlashProvider: { _ in nil }, // slash は miss → 背景走査
            asyncFileProvider: { _ in [] },
            cachedFileProvider: { term in term == "f" ? [fileCand("found.txt")] : nil } // file は warm
        )

        controller.update(text: "/s", cursorUTF16: 2)
        try await waitUntil { slashGate.pendingTerms().contains("s") }
        #expect(controller.isScanning == true)

        // file へ切替（warm 同期）。slash 走査は無効化され isScanning=false。
        controller.update(text: "@f", cursorUTF16: 2)
        #expect(controller.candidates.map(\.title) == ["found.txt"])
        #expect(controller.isScanning == false)

        // 遅延した slash 結果は採用されない。
        slashGate.release(term: "s", with: [slashCand("/slash-late")])
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.candidates.map(\.title) == ["found.txt"], "遅延 slash 結果が file 候補を上書きした")
        #expect(controller.isScanning == false)
    }

    // (4b) 逆方向: slash warm 同期反映が、in-flight の file 走査を無効化する（遅延 file 結果を破棄）。
    @Test @MainActor
    func slashWarmHit_invalidatesPendingFileScan() async throws {
        let fileGate = SlashGatedProvider()
        let controller = ComposerSuggestionController(
            asyncSlashProvider: { _ in [] },
            cachedSlashProvider: { term in term == "h" ? [slashCand("/help")] : nil }, // slash は warm
            asyncFileProvider: fileGate.provider,
            cachedFileProvider: { _ in nil } // file は miss → 背景走査
        )

        controller.update(text: "@f", cursorUTF16: 2)
        try await waitUntil { fileGate.pendingTerms().contains("f") }
        #expect(controller.isScanning == true)

        // slash へ切替（warm 同期）。file 走査は無効化され isScanning=false。
        controller.update(text: "/h", cursorUTF16: 2)
        #expect(controller.candidates.map(\.title) == ["/help"])
        #expect(controller.isScanning == false)

        fileGate.release(term: "f", with: [fileCand("late-file.txt")])
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.candidates.map(\.title) == ["/help"], "遅延 file 結果が slash 候補を上書きした")
        #expect(controller.isScanning == false)
    }

    // (5) dismiss: 走査中でも即クリア＋遅延結果は候補を復活させない。
    @Test @MainActor
    func dismissDuringSlashScan_lateResultDoesNotResurrect() async throws {
        let slashGate = SlashGatedProvider()
        let controller = ComposerSuggestionController(
            asyncSlashProvider: slashGate.provider,
            cachedSlashProvider: { _ in nil },
            asyncFileProvider: { _ in [] },
            cachedFileProvider: { _ in nil }
        )

        controller.update(text: "/q", cursorUTF16: 2)
        try await waitUntil { slashGate.pendingTerms().contains("q") }
        #expect(controller.isScanning == true)

        // トリガーなしテキストへ → dismiss。
        controller.update(text: "plain", cursorUTF16: 5)
        #expect(controller.candidates.isEmpty)
        #expect(controller.isScanning == false)

        slashGate.release(term: "q", with: [slashCand("/ghost")])
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.candidates.isEmpty, "dismiss 後に遅延 slash 結果が候補を復活させた")
        #expect(controller.isScanning == false)
    }
}
