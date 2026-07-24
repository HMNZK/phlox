import Testing
import AgentDomain
@testable import SessionFeature

/// 凍結受け入れテスト（PM 著・実装役は編集禁止。ハーネス欠陥を見つけた場合のみ PM 承認の上で修理可）。
///
/// 契約: 表示用の「実効セッション状態」は、背景/非同期作業が続いている間（isProcessing == true）
/// だけ、生の `.idle` を `.running` へ表示上昇格させる。これにより「メインターン完了で status は
/// idle でも、背景タスク/サブエージェントが動いている間は表示が実行中を保つ」を保証する。
/// `.idle` 以外の状態（error/awaiting/completed/starting）は isProcessing に依らず昇格しない。
@Suite("SessionDisplayStatus resolve contract (frozen)")
struct SessionDisplayStatusAcceptanceTests {
    @Test("idle + processing → running（desync の核）")
    func idleProcessingBecomesRunning() {
        #expect(SessionDisplayStatus.resolve(rawStatus: .idle, isProcessing: true) == .running)
    }

    @Test("idle + not processing → idle（純粋な完了はそのまま）")
    func idleNotProcessingStaysIdle() {
        #expect(SessionDisplayStatus.resolve(rawStatus: .idle, isProcessing: false) == .idle)
    }

    @Test("running は processing の有無に依らず running")
    func runningStaysRunning() {
        #expect(SessionDisplayStatus.resolve(rawStatus: .running, isProcessing: true) == .running)
        #expect(SessionDisplayStatus.resolve(rawStatus: .running, isProcessing: false) == .running)
    }

    @Test("idle 以外は processing でも昇格しない")
    func nonIdleNotPromoted() {
        #expect(SessionDisplayStatus.resolve(rawStatus: .error(message: "x"), isProcessing: true) == .error(message: "x"))
        #expect(SessionDisplayStatus.resolve(rawStatus: .awaitingApproval, isProcessing: true) == .awaitingApproval)
        #expect(SessionDisplayStatus.resolve(rawStatus: .awaitingUserQuestion, isProcessing: true) == .awaitingUserQuestion)
        #expect(SessionDisplayStatus.resolve(rawStatus: .completed, isProcessing: true) == .completed)
        #expect(SessionDisplayStatus.resolve(rawStatus: .starting, isProcessing: true) == .starting)
    }
}
