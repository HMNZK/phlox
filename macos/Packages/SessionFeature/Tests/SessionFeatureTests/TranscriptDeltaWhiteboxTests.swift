import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-3 白箱テスト（実装役の追加テスト。境界と内部不変条件を突く）。
// カーソル符号化・prefix ハッシュ照合・全変更経路での健全性を直接検証する。

@Suite struct TranscriptDeltaCursorWhiteboxTests {
    private func item(_ id: String, _ text: String) -> ChatItem {
        .agentMessage(id: id, text: text, timestamp: Date(timeIntervalSince1970: 0))
    }

    // MARK: - encode / parse ラウンドトリップ

    @Test func encodeParseRoundTrip() {
        let items = [item("a", "1"), item("b", "2")]
        let cursor = TranscriptDeltaCursor.encode(items)
        let parsed = TranscriptDeltaCursor.parse(cursor)
        #expect(parsed?.count == 2)
        #expect(parsed?.hash == TranscriptDeltaCursor.hash(items))
    }

    @Test func emptyTranscriptEncodesCountZero() {
        let cursor = TranscriptDeltaCursor.encode([])
        #expect(cursor.hasPrefix("0:"))
        #expect(TranscriptDeltaCursor.parse(cursor)?.count == 0)
    }

    // MARK: - parse の頑健性（不正カーソルは nil）

    @Test func parseRejectsMalformedCursors() {
        #expect(TranscriptDeltaCursor.parse("") == nil)
        #expect(TranscriptDeltaCursor.parse("abc") == nil)
        #expect(TranscriptDeltaCursor.parse("2") == nil)
        #expect(TranscriptDeltaCursor.parse("2:") == nil)
        #expect(TranscriptDeltaCursor.parse(":ff") == nil)
        #expect(TranscriptDeltaCursor.parse("-1:ff") == nil)
        #expect(TranscriptDeltaCursor.parse("2:zz") == nil)
    }

    // MARK: - ハッシュの識別力

    @Test func hashDistinguishesInPlaceEdit() {
        let before = [item("a", "hello"), item("b", "world")]
        let afterEdit = [item("a", "hello!!"), item("b", "world")]  // a を編集
        #expect(TranscriptDeltaCursor.hash(before) != TranscriptDeltaCursor.hash(afterEdit))
    }

    @Test func hashIsStableForIdenticalContentIgnoringTimestamp() {
        let t1 = ChatItem.agentMessage(id: "a", text: "x", timestamp: Date(timeIntervalSince1970: 100))
        let t2 = ChatItem.agentMessage(id: "a", text: "x", timestamp: Date(timeIntervalSince1970: 999))
        // timestamp のみ違い、クライアント観測内容は同一 → ハッシュ一致（誤 snapshot を出さない）
        #expect(TranscriptDeltaCursor.hash([t1]) == TranscriptDeltaCursor.hash([t2]))
    }

    @Test func hashDistinguishesItemBoundaries() {
        // 連結時のフィールド衝突がないこと（"ab"+"c" ≠ "a"+"bc"）
        let a = [item("ab", ""), item("c", "")]
        let b = [item("a", ""), item("bc", "")]
        #expect(TranscriptDeltaCursor.hash(a) != TranscriptDeltaCursor.hash(b))
    }

    // 区切り文字がフィールド値に含まれてもフィールド境界を跨いだ aliasing が起きないこと
    // （長さプレフィックス枠取りの回帰テスト。stage2 レビュー指摘の再現）
    @Test func commandFieldsCannotAliasCursorHash() {
        let date = Date(timeIntervalSince1970: 0)
        let before: [ChatItem] = [
            .commandExecution(id: "cmd", command: "a", output: "b\u{1}c", timestamp: date),
        ]
        let after: [ChatItem] = [
            .commandExecution(id: "cmd", command: "a\u{1}b", output: "c", timestamp: date),
        ]
        #expect(before != after)
        #expect(TranscriptDeltaCursor.hash(before) != TranscriptDeltaCursor.hash(after))
    }

    @Test func fileChangeFieldsCannotAliasCursorHash() {
        let date = Date(timeIntervalSince1970: 0)
        let before: [ChatItem] = [
            .fileChange(id: "f", changes: [
                FilePatchChange(path: "a", diff: "b\u{1}c", kind: "d"),
            ], timestamp: date),
        ]
        let after: [ChatItem] = [
            .fileChange(id: "f", changes: [
                FilePatchChange(path: "a", diff: "b", kind: "c\u{1}d"),
            ], timestamp: date),
        ]
        #expect(before != after)
        #expect(TranscriptDeltaCursor.hash(before) != TranscriptDeltaCursor.hash(after))
    }

    // 配列 arity（要素数）の食い違いを捕捉する（空要素の追加が snapshot を誘発）
    @Test func fileChangeArityIsDistinguished() {
        let date = Date(timeIntervalSince1970: 0)
        let one: [ChatItem] = [
            .fileChange(id: "f", changes: [FilePatchChange(path: "", diff: "", kind: nil)], timestamp: date),
        ]
        let two: [ChatItem] = [
            .fileChange(id: "f", changes: [
                FilePatchChange(path: "", diff: "", kind: nil),
                FilePatchChange(path: "", diff: "", kind: nil),
            ], timestamp: date),
        ]
        #expect(TranscriptDeltaCursor.hash(one) != TranscriptDeltaCursor.hash(two))
    }

    // Optional は nil と空文字を弁別する（存在フラグの枠取り）
    @Test func optionalNilVsEmptyStringDistinguished() {
        let date = Date(timeIntervalSince1970: 0)
        let nilCommand: [ChatItem] = [
            .commandExecution(id: "c", command: nil, output: "o", timestamp: date),
        ]
        let emptyCommand: [ChatItem] = [
            .commandExecution(id: "c", command: "", output: "o", timestamp: date),
        ]
        #expect(nilCommand != emptyCommand)
        #expect(TranscriptDeltaCursor.hash(nilCommand) != TranscriptDeltaCursor.hash(emptyCommand))
    }
}

@MainActor
private func makeVM(_ client: EventYieldingStructuredClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@MainActor
private func waitFor(_ condition: @escaping () -> Bool) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < 1_000_000_000 else {
            Issue.record("Timed out")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        elapsed += 10_000_000
    }
}

@Suite struct TranscriptDeltaViewModelWhiteboxTests {
    // カーソル直後の1件 append は差分1件（境界）
    @Test @MainActor func singleAppendAfterCursorReturnsExactlyOneItem() async throws {
        let client = EventYieldingStructuredClient()
        let vm = makeVM(client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        client.yield(.agentMessageDelta(itemId: "a1", "one"))
        try await waitFor { vm.transcript.count == 1 }
        let cursor = vm.transcriptDelta(since: nil).cursor

        client.yield(.agentMessageDelta(itemId: "a2", "two"))
        try await waitFor { vm.transcript.count == 2 }

        let delta = vm.transcriptDelta(since: cursor)
        #expect(delta.items.count == 1)
        #expect(delta.items.first?.id == "a2")
        #expect(delta.isSnapshot == false)
    }

    // 末尾メッセージへのストリーミング追記（最後の項目が cursor より後なら差分維持できる）
    @Test @MainActor func streamingIntoLastItemAfterCursorStaysDelta() async throws {
        let client = EventYieldingStructuredClient()
        let vm = makeVM(client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        client.yield(.agentMessageDelta(itemId: "a1", "one"))
        try await waitFor { vm.transcript.count == 1 }
        // cursor は a1 の前（transcript 空相当ではなく count=1 時点）。ここでは count=1 の cursor を取る。
        let cursor = vm.transcriptDelta(since: nil).cursor

        // a2 が新規追加され、さらに a2 にストリーミング追記（a2 は cursor より後＝prefix 不変）
        client.yield(.agentMessageDelta(itemId: "a2", "two"))
        try await waitFor { vm.transcript.count == 2 }
        client.yield(.agentMessageDelta(itemId: "a2", " more"))
        try await waitFor {
            if case .agentMessage(_, let text, _)? = vm.transcript.last { return text.contains("more") }
            return false
        }

        let delta = vm.transcriptDelta(since: cursor)
        // prefix（a1）は不変なので差分維持。a2 の最新内容を返す
        #expect(delta.isSnapshot == false)
        #expect(delta.items.count == 1)
        if case .agentMessage(let id, let text, _)? = delta.items.first {
            #expect(id == "a2")
            #expect(text == "two more")
        } else {
            Issue.record("expected a2")
        }
    }

    // 全量置換経路（restore 相当の setTranscript）後は snapshot へ倒れる
    @Test @MainActor func replaceOfPrefixItemForcesSnapshot() async throws {
        let client = EventYieldingStructuredClient()
        let vm = makeVM(client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        client.yield(.agentMessageDelta(itemId: "a1", "one"))
        try await waitFor { vm.transcript.count == 1 }
        client.yield(.agentMessageDelta(itemId: "a2", "two"))
        try await waitFor { vm.transcript.count == 2 }
        let cursor = vm.transcriptDelta(since: nil).cursor

        // prefix の a1 を編集（in-place replace 経路）
        client.yield(.agentMessageDelta(itemId: "a1", " edited"))
        try await waitFor {
            if case .agentMessage(let id, let text, _) = vm.transcript[0] {
                return id == "a1" && text.contains("edited")
            }
            return false
        }

        let delta = vm.transcriptDelta(since: cursor)
        #expect(delta.isSnapshot == true)
        #expect(delta.items.count == vm.transcript.count)
    }

    // 非常に古い（別プロセス相当の桁違い）カーソルは snapshot
    @Test @MainActor func staleCursorWithHugeCountForcesSnapshot() async throws {
        let client = EventYieldingStructuredClient()
        let vm = makeVM(client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        client.yield(.agentMessageDelta(itemId: "a1", "one"))
        try await waitFor { vm.transcript.count == 1 }

        let delta = vm.transcriptDelta(since: "9999:deadbeef")
        #expect(delta.isSnapshot == true)
        #expect(delta.items.count == 1)
    }
}
