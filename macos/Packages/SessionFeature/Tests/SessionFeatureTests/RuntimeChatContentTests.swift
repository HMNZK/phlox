import AgentDomain
import Foundation
import Testing
@testable import SessionFeature

@Suite @MainActor struct RuntimeChatContentTests {
    @Test func escapedHugeItemHasBoundedPageAndRecoverableBytes() throws {
        var snapshot = chatSnapshot(items: [
            .commandExecution(id: "large-command", command: "run", output: String(repeating: "\\", count: 3_000_000), timestamp: .distantPast),
        ])
        snapshot.transcriptRevision = 7
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let request = SessionRuntimeContentRequest(sessionID: snapshot.id, executionID: snapshot.executionID, target: .chatTail)

        let response = try session.runtimeContent(for: request)
        let encoded = try JSONEncoder().encode(response)

        #expect(encoded.count <= 4 * 1024 * 1024)
        guard case .chatPage(let page) = response,
              case .oversized(let marker)? = page.entries.first else {
            Issue.record("巨大項目の明示 marker がありません")
            return
        }
        #expect(marker.id == "large-command")
        #expect(marker.totalBytes > 4 * 1024 * 1024)
        let chunk = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID,
            target: .itemChunk(id: marker.id, digest: marker.digest, offset: 0)))
        guard case .chunk(let part) = chunk else {
            Issue.record("巨大項目の分割取得に失敗しました")
            return
        }
        #expect(try JSONEncoder().encode(chunk).count <= 4 * 1024 * 1024)
        #expect(part.offset == 0)
        #expect(!part.bytes.isEmpty)
        #expect(part.nextOffset != nil)
    }

    @Test func oldPageSurvivesLaterAppendAndEditButRejectsEarlierEdit() throws {
        let first = ChatItem.agentMessage(id: "first", text: "original", timestamp: .distantPast)
        let large = String(repeating: "m", count: 900_000)
        var snapshot = chatSnapshot(items: [first,
            .agentMessage(id: "second", text: large, timestamp: .distantPast),
            .agentMessage(id: "third", text: large, timestamp: .distantPast),
            .agentMessage(id: "fourth", text: large, timestamp: .distantPast),
            .agentMessage(id: "fifth", text: large, timestamp: .distantPast),
            .agentMessage(id: "last", text: large, timestamp: .distantPast)])
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let tail = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatTail))
        guard case .chatPage(let page) = tail, let cursor = page.olderCursor else {
            Issue.record("過去ページの cursor がありません")
            return
        }
        snapshot.transcript.append(.agentMessage(id: "appended", text: "new", timestamp: .distantPast))
        snapshot.transcriptRevision += 1
        try session.applyRuntimeSnapshot(snapshot)

        let afterAppend = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatBefore(cursor: cursor)))

        guard case .chatPage(let older) = afterAppend else {
            Issue.record("追記後に過去ページを取得できません")
            return
        }
        #expect(older.entries.count > 0)
        snapshot.transcript[6] = .agentMessage(id: "appended", text: "newer", timestamp: .distantPast)
        snapshot.transcriptRevision += 1
        try session.applyRuntimeSnapshot(snapshot)
        let afterLaterEdit = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatBefore(cursor: cursor)))
        guard case .chatPage(let afterEdit) = afterLaterEdit else {
            Issue.record("後方項目の編集で過去ページを失いました")
            return
        }
        #expect(afterEdit.entries.count > 0)
        snapshot.transcript[0] = .agentMessage(id: "first", text: "edited", timestamp: .distantPast)
        snapshot.transcriptRevision += 1
        try session.applyRuntimeSnapshot(snapshot)
        do {
            _ = try session.runtimeContent(for: .init(sessionID: snapshot.id,
                executionID: snapshot.executionID, target: .chatBefore(cursor: cursor)))
            Issue.record("変更前の位置を受理しました")
        } catch {
            #expect(error as? SessionRuntimeContentError == .staleContent)
        }
    }

    @Test func changingOversizedItemRejectsOldRemainingChunks() throws {
        var snapshot = chatSnapshot(items: [
            .commandExecution(id: "running-command", command: "run", output: String(repeating: "x", count: 3_000_000), timestamp: .distantPast),
        ])
        snapshot.transcriptRevision = 7
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let tail = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatTail))
        guard case .chatPage(let page) = tail,
              case .oversized(let marker)? = page.entries.first else {
            Issue.record("分割対象の項目がありません")
            return
        }
        let first = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .itemChunk(id: marker.id, digest: marker.digest, offset: 0)))
        guard case .chunk(let chunk) = first, let nextOffset = chunk.nextOffset else {
            Issue.record("続きの位置がありません")
            return
        }
        snapshot.transcript[0] = .commandExecution(id: "running-command", command: "run",
            output: String(repeating: "y", count: 3_000_000), timestamp: .distantPast)
        snapshot.transcriptRevision += 1
        try session.applyRuntimeSnapshot(snapshot)

        #expect(throws: SessionRuntimeContentError.staleContent) {
            try session.runtimeContent(for: .init(sessionID: snapshot.id,
                executionID: snapshot.executionID,
                target: .itemChunk(id: marker.id, digest: marker.digest, offset: nextOffset)))
        }
    }

    @Test func newExecutionCannotReuseOldItemChunksAtSameRevision() throws {
        var snapshot = chatSnapshot(items: [
            .agentMessage(id: "message", text: String(repeating: "x", count: 3_000_000), timestamp: .distantPast),
        ])
        snapshot.transcriptRevision = 7
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let tail = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatTail))
        guard case .chatPage(let page) = tail,
              case .oversized(let marker)? = page.entries.first else {
            Issue.record("分割対象の項目がありません")
            return
        }
        let first = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID,
            target: .itemChunk(id: marker.id, digest: marker.digest, offset: 0)))
        guard case .chunk(let chunk) = first, let nextOffset = chunk.nextOffset else {
            Issue.record("続きの位置がありません")
            return
        }
        snapshot.executionID = UUID(uuidString: "AA37E73F-6C0C-4267-8599-96381623DB7A")!
        snapshot.transcript[0] = .agentMessage(id: "message", text: String(repeating: "y", count: 3_000_000), timestamp: .distantPast)
        try session.applyRuntimeSnapshot(snapshot)

        #expect(throws: SessionRuntimeContentError.staleContent) {
            try session.runtimeContent(for: .init(sessionID: snapshot.id,
                executionID: snapshot.executionID,
                target: .itemChunk(id: marker.id, digest: marker.digest, offset: nextOffset)))
        }
    }

    @Test func staleExecutionCannotReadNewItem() throws {
        let snapshot = chatSnapshot(items: [.agentMessage(id: "message", text: "secret", timestamp: .distantPast)])
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }

        do {
            _ = try session.runtimeContent(for: .init(sessionID: snapshot.id,
                executionID: UUID(), target: .chatTail))
            Issue.record("古い実行世代の本文を受理しました")
        } catch {
            #expect(error as? SessionRuntimeContentError == .staleContent)
        }
    }

    @Test func largeApprovalIsMarkedAndRecoverable() throws {
        var snapshot = chatSnapshot(items: [])
        let largeID = UUID(uuidString: "1CEFD9E3-5BE5-4884-81D4-CF284EEB7DE0")!
        snapshot.pendingApprovals = [ChatApprovalRequest(id: largeID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "approval-item",
            prompt: String(repeating: "\\", count: 3_000_000))]
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }

        let response = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .pending(cursor: nil)))

        #expect(try JSONEncoder().encode(response).count <= 4 * 1024 * 1024)
        guard case .pendingPage(let page) = response,
              case .oversized(let marker)? = page.entries.first else {
            Issue.record("巨大な承認全文の marker がありません")
            return
        }
        #expect(marker.id == largeID.uuidString)
        let chunk = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID,
            target: .approvalChunk(id: largeID, digest: marker.digest, offset: 0)))
        guard case .chunk(let part) = chunk else {
            Issue.record("承認全文の分割取得に失敗しました")
            return
        }
        #expect(!part.bytes.isEmpty)
        #expect(try JSONEncoder().encode(chunk).count <= 4 * 1024 * 1024)
    }

    @Test func changingPendingApprovalRejectsOldRemainingChunks() throws {
        var snapshot = chatSnapshot(items: [])
        let approvalID = UUID(uuidString: "90E14C32-B14D-488D-9C3A-8B30C53F82A9")!
        snapshot.pendingApprovals = [ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "command",
            prompt: String(repeating: "a", count: 3_000_000))]
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let pending = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .pending(cursor: nil)))
        guard case .pendingPage(let page) = pending,
              case .oversized(let marker)? = page.entries.first else {
            Issue.record("分割対象の承認がありません")
            return
        }
        let first = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID,
            target: .approvalChunk(id: approvalID, digest: marker.digest, offset: 0)))
        guard case .chunk(let chunk) = first, let nextOffset = chunk.nextOffset else {
            Issue.record("承認の続きの位置がありません")
            return
        }
        snapshot.pendingApprovals[0] = ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "command",
            prompt: String(repeating: "b", count: 3_000_000))
        try session.applyRuntimeSnapshot(snapshot)

        #expect(throws: SessionRuntimeContentError.staleContent) {
            try session.runtimeContent(for: .init(sessionID: snapshot.id,
                executionID: snapshot.executionID,
                target: .approvalChunk(id: approvalID, digest: marker.digest, offset: nextOffset)))
        }
    }

    @Test func pendingApprovalsBeyondFirstPageRemainAccessible() throws {
        var snapshot = chatSnapshot(items: [])
        snapshot.pendingApprovals = approvalFixture(count: 18, prompt: String(repeating: "p", count: 300_000))
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }

        let first = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .pending(cursor: nil)))
        guard case .pendingPage(let firstPage) = first, let cursor = firstPage.nextCursor else {
            Issue.record("保留中の承認が1ページ目で黙って切れました")
            return
        }
        let second = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .pending(cursor: cursor)))

        guard case .pendingPage(let secondPage) = second else {
            Issue.record("保留中の承認の続きが取れません")
            return
        }
        #expect(firstPage.totalCount == 18)
        #expect(firstPage.entries.count < 18)
        #expect(secondPage.entries.count > 0)
        #expect(firstPage.entries.count + secondPage.entries.count == 18)
        #expect(secondPage.nextCursor == nil)
        #expect(try JSONEncoder().encode(first).count <= 4 * 1024 * 1024)
        #expect(try JSONEncoder().encode(second).count <= 4 * 1024 * 1024)
    }

    @Test func severalLargeMessagesFillBoundedPagesWithoutDroppingHistory() throws {
        let text = String(repeating: "m", count: 900_000)
        let items = (1...10).map { number in
            ChatItem.agentMessage(id: "message-\(number)", text: text, timestamp: .distantPast)
        }
        let snapshot = chatSnapshot(items: items)
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }

        let first = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatTail))
        guard case .chatPage(let firstPage) = first, let firstCursor = firstPage.olderCursor else {
            Issue.record("末尾ページの続きがありません")
            return
        }
        let second = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatBefore(cursor: firstCursor)))
        guard case .chatPage(let secondPage) = second, let secondCursor = secondPage.olderCursor else {
            Issue.record("中間ページの続きがありません")
            return
        }
        let third = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatBefore(cursor: secondCursor)))
        guard case .chatPage(let thirdPage) = third else {
            Issue.record("最初のページを取得できません")
            return
        }

        #expect(firstPage.startIndex == 6)
        #expect(secondPage.startIndex == 2)
        #expect(thirdPage.startIndex == 0)
        #expect(firstPage.entries.count == 4)
        #expect(secondPage.entries.count == 4)
        #expect(thirdPage.entries.count == 2)
        #expect(thirdPage.olderCursor == nil)
        #expect(try JSONEncoder().encode(first).count <= 4 * 1024 * 1024)
        #expect(try JSONEncoder().encode(second).count <= 4 * 1024 * 1024)
        #expect(try JSONEncoder().encode(third).count <= 4 * 1024 * 1024)
    }

    @Test func largePresentationContinuesAcrossUnrelatedChatRefresh() throws {
        var snapshot = chatSnapshot(items: [
            .agentMessage(id: "answer", text: "still visible", timestamp: .distantPast),
        ])
        snapshot.availableSlashCommands = Array(repeating: "/" + String(repeating: "x", count: 1_000), count: 6_000)
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let first = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatPresentation(offset: 0, digest: nil)))
        guard case .presentationChunk(let firstChunk) = first, let nextOffset = firstChunk.nextOffset else {
            Issue.record("補助情報の続きがありません")
            return
        }

        _ = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatTail))
        let second = try session.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID,
            target: .chatPresentation(offset: nextOffset, digest: firstChunk.digest)))

        guard case .presentationChunk(let secondChunk) = second else {
            Issue.record("補助情報の続きが取れません")
            return
        }
        #expect(secondChunk.digest == firstChunk.digest)
        #expect(secondChunk.offset == nextOffset)
        #expect(secondChunk.totalBytes == firstChunk.totalBytes)
        #expect(!secondChunk.bytes.isEmpty)
    }

    @Test func oversizedPresentationFailureEndsWhenDisplayListShrinks() throws {
        var snapshot = chatSnapshot(items: [])
        snapshot.availableSlashCommands = Array(repeating: "/" + String(repeating: "x", count: 600), count: 40_000)
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let request = SessionRuntimeContentRequest(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatPresentation(offset: 0, digest: nil))

        #expect(throws: SessionRuntimeContentError.invalidRequest) {
            try session.runtimeContent(for: request)
        }
        snapshot.availableSlashCommands = ["/status"]
        try session.applyRuntimeSnapshot(snapshot)
        let recovered = try session.runtimeContent(for: request)

        guard case .presentationChunk(let chunk) = recovered else {
            Issue.record("一覧縮小後の補助情報が取れません")
            return
        }
        let value = try JSONDecoder().decode(SessionRuntimeChatPresentation.self, from: chunk.bytes)
        #expect(value.availableSlashCommands == ["/status"])
        #expect(chunk.nextOffset == nil)
    }

    private func approvalFixture(count: Int, prompt: String) -> [ChatApprovalRequest] {
        (1...count).map { number in
            ChatApprovalRequest(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
                kind: .command, threadId: "thread", turnId: "turn", itemId: "item-\(number)", prompt: prompt)
        }
    }

    private func chatSnapshot(items: [ChatItem]) -> SessionRuntimeChatSnapshot {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.transcript = items
        return snapshot
    }
}
