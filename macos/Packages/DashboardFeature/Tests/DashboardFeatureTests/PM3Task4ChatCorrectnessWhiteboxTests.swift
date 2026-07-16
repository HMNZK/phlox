import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-4 白箱テスト（実装役著述）。
// 契約: tasks/task-4.md の名指しハザード resume-exactly-once（cancelAll と respond の競合で
// 同一 continuation を2回 resume しない・0回にもしない）と cancelAll の冪等性を符号化する。
// acceptance（PM3Task4ChatSendTerminateAcceptanceTests）は VM 経由の観測を凍結しているが、
// ここでは ChatApprovalBroker を直接叩き、並行 interleaving と mixed-kind 経路を突く。

/// NSLock ベースの Sendable カウンタ（waitUntil の同期クロージャから読める）。
private final class WBCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    func get() -> Int { lock.withLock { value } }
}

/// broker.requests から観測した承認 id を集める（単一消費者ストリームを白箱で自分が消費）。
private final class WBIDCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [UUID] = []
    func append(_ id: UUID) { lock.withLock { ids.append(id) } }
    func count() -> Int { lock.withLock { ids.count } }
    func all() -> [UUID] { lock.withLock { ids } }
}

private func wbCommandApproval(index: Int) -> CommandExecutionApprovalRequest {
    let json = """
    {"threadId":"t","turnId":"turn","itemId":"item-\(index)","startedAtMs":0,"command":"echo \(index)","reason":"確認"}
    """
    return try! JSONDecoder().decode(CommandExecutionApprovalRequest.self, from: Data(json.utf8))
}

private func wbPermissionsApproval(index: Int) -> PermissionsApprovalRequest {
    let json = """
    {"threadId":"t","turnId":"turn","itemId":"perm-\(index)","startedAtMs":0,"cwd":"/tmp","reason":"権限","permissions":{"tools":["Bash"]}}
    """
    return try! JSONDecoder().decode(PermissionsApprovalRequest.self, from: Data(json.utf8))
}

@Suite(.serialized)
struct PM3Task4ChatCorrectnessWhiteboxTests {

    /// resume-exactly-once: respond と cancelAll を同時に走らせても、各 continuation は
    /// ちょうど1回だけ resume される（2回なら CheckedContinuation がプロセスをクラッシュさせる／
    /// 0回なら await が復帰せず waitUntil がタイムアウトする）。多数反復で interleaving を揺らす。
    @Test @MainActor
    func cancelAll_racingWithRespond_resumesEachContinuationExactlyOnce() async throws {
        let iterations = 40
        let perIteration = 6
        for _ in 0..<iterations {
            let broker = ChatApprovalBroker()
            let completed = WBCounter()
            let collector = WBIDCollector()

            // 承認要求ストリームを消費して id を得る（respond に渡すため）。
            let consumer = Task {
                var seen = 0
                let stream = await broker.requests
                for await approval in stream {
                    collector.append(approval.id)
                    seen += 1
                    if seen == perIteration { break }
                }
            }

            // pending を perIteration 件積む。各 handler は解決されるまで await する。
            for i in 0..<perIteration {
                let req = wbCommandApproval(index: i)
                Task.detached {
                    _ = try? await broker.serverRequestHandler(.commandExecutionApproval(req))
                    completed.increment()
                }
            }

            // 全 pending が登録され id が出そろうまで待つ。
            try await waitUntil { collector.count() == perIteration }
            let ids = collector.all()

            // respond（各 id を並行に）と cancelAll を同時発火する。
            async let responders: Void = withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask { await broker.respond(to: id, decision: .accept) }
                }
            }
            async let canceller: Void = broker.cancelAll()
            _ = await (responders, canceller)

            // 全 continuation が resume されて await が復帰する（リークしない）。
            try await waitUntil { completed.get() == perIteration }
            consumer.cancel()
        }
    }

    /// cancelAll は pending を全て解決する。mixed-kind（command と permissions）でも
    /// resolve の両分岐を通って await が復帰する。
    @Test @MainActor
    func cancelAll_resolvesAllPending_acrossKinds() async throws {
        let broker = ChatApprovalBroker()
        let completed = WBCounter()
        let collector = WBIDCollector()
        let total = 4

        let consumer = Task {
            var seen = 0
            let stream = await broker.requests
            for await approval in stream {
                collector.append(approval.id)
                seen += 1
                if seen == total { break }
            }
        }

        for i in 0..<2 {
            let cmd = wbCommandApproval(index: i)
            Task.detached {
                _ = try? await broker.serverRequestHandler(.commandExecutionApproval(cmd))
                completed.increment()
            }
            let perm = wbPermissionsApproval(index: i)
            Task.detached {
                _ = try? await broker.serverRequestHandler(.permissionsApproval(perm))
                completed.increment()
            }
        }

        try await waitUntil { collector.count() == total }
        #expect(completed.get() == 0, "cancelAll 前に解決してしまっている")

        await broker.cancelAll()
        try await waitUntil { completed.get() == total }
        consumer.cancel()
    }

    /// cancelAll は冪等（pending 空での2回目以降は no-op でクラッシュしない）。
    @Test @MainActor
    func cancelAll_isIdempotentWhenNoPending() async {
        let broker = ChatApprovalBroker()
        await broker.cancelAll()
        await broker.cancelAll()
    }

    /// terminal 化（cancelAll）後に到達した承認要求は pending に積まれず即時に否認で解決される
    /// （リークしない）。stage2 差し戻しの根本原因（close 進行中の遅延到達要求リーク）を broker 単体で突く。
    @Test @MainActor
    func handle_afterCancelAll_resolvesImmediatelyWithoutLeaking() async throws {
        let broker = ChatApprovalBroker()
        await broker.cancelAll()  // terminal 化

        let completed = WBCounter()
        let req = wbCommandApproval(index: 0)
        let late = Task.detached {
            _ = try? await broker.serverRequestHandler(.commandExecutionApproval(req))
            completed.increment()
        }
        // 即時に復帰する（pending へ積まれ無期限に await されない）。
        try await waitUntil { completed.get() == 1 }
        late.cancel()
    }

    /// respond で解決済みの id を cancelAll が二重に resume しない（respond 先行→cancelAll）。
    @Test @MainActor
    func cancelAll_afterRespond_doesNotDoubleResume() async throws {
        let broker = ChatApprovalBroker()
        let completed = WBCounter()
        let collector = WBIDCollector()

        let consumer = Task {
            let stream = await broker.requests
            for await approval in stream {
                collector.append(approval.id)
                break
            }
        }

        let req = wbCommandApproval(index: 0)
        Task.detached {
            _ = try? await broker.serverRequestHandler(.commandExecutionApproval(req))
            completed.increment()
        }

        try await waitUntil { collector.count() == 1 }
        let id = collector.all()[0]

        await broker.respond(to: id, decision: .accept)
        try await waitUntil { completed.get() == 1 }
        // 解決済み id に対する cancelAll は no-op（二重 resume すればここでクラッシュする）。
        await broker.cancelAll()
        #expect(completed.get() == 1)
        consumer.cancel()
    }
}
