import AgentDomain
import DashboardFeature
import Foundation
import SessionFeature
import StructuredChatKit
import Testing
@testable import AppBootstrap

@Suite struct SessionRuntimeSnapshotUpdateTests {
    @Test func arrayPatchPreservesAppendReplacementTruncationAndEmpty() throws {
        let before = [1, 2, 3, 4]
        for after in [[1, 2, 3, 4, 5], [1, 2, 3, 9], [1, 9, 3, 4], [1, 2], [], before] {
            let patch = RuntimeArrayPatch(replacing: before, with: after)
            #expect(try patch.applying(to: before) == after)
        }
        #expect(throws: SessionRuntimeConnectionError.self) {
            try RuntimeArrayPatch<Int>(prefixCount: -1, suffix: []).applying(to: before)
        }
        #expect(throws: SessionRuntimeConnectionError.self) {
            try RuntimeArrayPatch<Int>(prefixCount: 5, suffix: []).applying(to: before)
        }
    }

    @Test func fullAndChangedStatesRoundTripWithoutLosingHistory() throws {
        let initial = chat()
        let first = try prepare(initial, sequence: 1)
        #expect(try canonical(first.update.restoring(base: nil).envelope.snapshot) == canonical(snapshot(initial)))
        var changed = initial
        changed.transcript[0] = item("first", text: "途中の修正")
        changed.transcript.append(item("last", text: "追加"))
        changed.rawEventLog.append("new event")
        changed.subAgents.transcripts["child"] = [item("child-first", text: "子の更新")]
        changed.status = .running
        changed.transcriptRevision += 1
        let next = try prepare(changed, sequence: 2, base: first.baseline)
        let wire = try JSONEncoder().encode(next.update)
        let decoded = try JSONDecoder().decode(SessionRuntimeSnapshotUpdate.self, from: wire)
        #expect(try canonical(decoded.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(changed)))

        changed.transcript = []
        changed.subAgents.transcripts = [:]
        changed.rawEventLog = []
        let empty = try prepare(changed, sequence: 3, base: next.baseline)
        #expect(try canonical(empty.update.restoring(base: next.baseline).envelope.snapshot) == canonical(snapshot(changed)))
    }

    @Test func unknownBaseDeletedSessionsAndExecutionChangesUseCompleteState() async throws {
        let encoder = SessionRuntimeSnapshotEncoder()
        let original = chat()
        _ = try await encoder.encode(envelope(original, sequence: 1), baseSequence: nil, updates: true)
        var replacement = original
        replacement.executionID = UUID()
        replacement.transcript = [item("new", text: "別の実行")]
        let data = try await encoder.encode(envelope(replacement, sequence: 2), baseSequence: 1, updates: true)
        let replaced = try JSONDecoder().decode(SessionRuntimeSnapshotUpdate.self, from: data)
        #expect(replaced.chatPatches.isEmpty)
        #expect(try replaced.restoring(base: prepare(original, sequence: 1).baseline).envelope.snapshot.sessions.count == 1)

        let deleted = SessionRuntimeSnapshotEnvelope(sequence: 3, snapshot: .init(projects: [], sessions: [], availableAgentKinds: []))
        _ = try await encoder.encode(deleted, baseSequence: 2, updates: true)
        let expired = try await encoder.encode(envelope(original, sequence: 4), baseSequence: 1, updates: true)
        let full = try JSONDecoder().decode(SessionRuntimeSnapshotUpdate.self, from: expired)
        #expect(full.baseSequence == nil)
        #expect(try canonical(full.restoring(base: nil).envelope.snapshot) == canonical(snapshot(original)))
    }

    @Test func eachConcurrentResponseUsesItsRequestedBaseline() throws {
        let original = chat()
        let base = try prepare(original, sequence: 1).baseline
        var second = original
        second.transcript.append(item("second", text: "2"))
        var third = original
        third.transcript[1] = item("third", text: "3")
        let olderResponse = try prepare(second, sequence: 2, base: base).update
        let newerResponse = try prepare(third, sequence: 3, base: base).update
        let receivedNewer = try newerResponse.restoring(base: base)
        #expect(try canonical(receivedNewer.envelope.snapshot) == canonical(snapshot(third)))
        #expect(try canonical(olderResponse.restoring(base: base).envelope.snapshot) == canonical(snapshot(second)))
        #expect(throws: SessionRuntimeConnectionError.self) { try olderResponse.restoring(base: receivedNewer) }
    }

    @Test func answeringAnEarlierQuestionPreservesLaterOutputAndNewChildContent() throws {
        var initial = chat()
        let question = ChatUserQuestion(question: "続けますか", header: "確認", options: [], multiSelect: false, id: "stable-question")
        initial.transcript.insert(.userQuestion(id: "question", requestId: "request", questions: [question],
            answers: nil, state: .pending, timestamp: .distantPast), at: 0)
        let first = try prepare(initial, sequence: 1)
        var answered = initial
        answered.transcript[0] = .userQuestion(id: "question", requestId: "request", questions: [question],
            answers: ["stable-question": ["続ける"]], state: .answered, timestamp: .distantPast)
        answered.subAgents.transcripts["new-child"] = [item("new-child-item", text: "新しい子")]
        let next = try prepare(answered, sequence: 2, base: first.baseline)
        #expect(next.update.chatPatches.first?.transcript.prefixCount == 0)
        #expect(try canonical(next.update.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(answered)))
    }

    @Test func malformedPatchesCannotClearOrDuplicateExistingContent() throws {
        let initial = chat()
        let first = try prepare(initial, sequence: 1)
        let valid = try prepare(initial, sequence: 2, base: first.baseline).update
        var missing = valid
        missing.chatPatches = []
        #expect(throws: SessionRuntimeConnectionError.self) { try missing.restoring(base: first.baseline) }
        var duplicated = valid
        duplicated.chatPatches.append(try #require(valid.chatPatches.first))
        #expect(throws: SessionRuntimeConnectionError.self) { try duplicated.restoring(base: first.baseline) }
        var wrongExecution = valid
        wrongExecution.chatPatches[0].executionID = UUID()
        #expect(throws: SessionRuntimeConnectionError.self) { try wrongExecution.restoring(base: first.baseline) }
        var absentChild = valid
        absentChild.chatPatches[0].subAgentTranscripts["missing"] = .init(prefixCount: 0, suffix: [])
        #expect(throws: SessionRuntimeConnectionError.self) { try absentChild.restoring(base: first.baseline) }
    }

    @Test func reconstructedSizeLimitCannotBeEvadedWithSmallUpdates() throws {
        var initial = chat()
        initial.transcript = [item("first", text: String(repeating: "a", count: 600))]
        initial.subAgents.transcripts = [:]
        let first = try prepare(initial, sequence: 1)
        let limit = first.baseline.encodedByteCount + 100
        var changed = initial
        changed.transcript.append(item("second", text: String(repeating: "b", count: 200)))
        #expect(throws: SessionRuntimeConnectionError.responseTooLarge) {
            try SessionRuntimeSnapshotUpdate.prepare(envelope(changed, sequence: 2), base: first.baseline, maximumBytes: limit)
        }
        let unrestricted = try prepare(changed, sequence: 2, base: first.baseline)
        #expect(throws: SessionRuntimeConnectionError.responseTooLarge) {
            try unrestricted.update.restoring(base: first.baseline, maximumBytes: limit)
        }
        #expect(first.baseline.encodedByteCount == (try JSONEncoder().encode(envelope(initial, sequence: 1))).count)
    }

    @Test func optionalPayloadsAndEscapedStringsKeepExactSizeAndNilSemantics() throws {
        var initial = chat()
        initial.transcript.append(item("escapes", text: "quotes\" slash/ backslash\\ control\n\t emoji🪻日本語"))
        initial.rawEventLog = ["\n\"/🪻"]
        initial.skillSelection = try JSONDecoder().decode(SessionRuntimeSkillSnapshot.self,
            from: Data(#"{"skills":[],"fingerprints":{"a":"quoted\"/日本語"},"isLoading":false,"isStale":true}"#.utf8))
        initial.historyEntries = [.init(sessionID: "history", preview: "履歴\n/", firstUserAt: nil,
            lastModified: Date(timeIntervalSince1970: 0), gitBranch: nil, fileURL: URL(fileURLWithPath: "/a/b"))]
        initial.historySummaries = try JSONDecoder().decode([String: ChatHistorySummary].self,
            from: Data(#"{"history":{"messageCount":3,"reachesLimit":false,"lastMessage":"summary/日本語"}}"#.utf8))
        let first = try prepare(initial, sequence: 1)
        #expect(first.baseline.encodedByteCount == (try JSONEncoder().encode(envelope(initial, sequence: 1))).count)
        let unchanged = try prepare(initial, sequence: 2, base: first.baseline)
        #expect(try canonical(unchanged.update.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(initial)))
        var cleared = initial
        cleared.skillSelection = nil
        cleared.historyEntries = []
        cleared.historySummaries = [:]
        let next = try prepare(cleared, sequence: 3, base: unchanged.baseline)
        #expect(next.baseline.encodedByteCount == (try JSONEncoder().encode(envelope(cleared, sequence: 3))).count)
        #expect(try canonical(next.update.restoring(base: unchanged.baseline).envelope.snapshot) == canonical(snapshot(cleared)))
    }

    @Test @MainActor func cancellationDoesNotEvictTheLastUsableServerBaseline() async throws {
        let encoder = SessionRuntimeSnapshotEncoder()
        let initial = chat()
        _ = try await encoder.encode(envelope(initial, sequence: 1), baseSequence: nil, updates: true)
        let cancelled = Task { try await encoder.encode(envelope(initial, sequence: 2), baseSequence: 1, updates: true) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let data = try await encoder.encode(envelope(initial, sequence: 3), baseSequence: 1, updates: true)
        #expect(try JSONDecoder().decode(SessionRuntimeSnapshotUpdate.self, from: data).baseSequence == 1)
    }

    @Test func largeHistoryTailUpdatesDoNotResendParentOrChildHistory() throws {
        var initial = chat()
        initial.transcript = (0..<2_200).map { item("parent-\($0)", text: String(repeating: "履歴", count: 150)) }
        initial.subAgents.transcripts["child"] = (0..<2_200).map { item("child-\($0)", text: String(repeating: "child history", count: 100)) }
        let first = try prepare(initial, sequence: 1)
        var changed = initial
        changed.transcript.append(item("parent-new", text: "新しい出力"))
        changed.subAgents.transcripts["child"]?.append(item("child-new", text: "new child output"))
        let next = try prepare(changed, sequence: 2, base: first.baseline)
        let fullBytes = try JSONEncoder().encode(next.baseline.envelope).count
        let updateBytes = try JSONEncoder().encode(next.update).count
        #expect(fullBytes > 4_000_000)
        #expect(updateBytes < 20_000)
        #expect(try canonical(next.update.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(changed)))
        #expect(next.baseline.encodedByteCount == fullBytes)
    }

    @Test func timestampChangesPreserveParentAndChildContentsAndExactSize() throws {
        var initial = chat()
        initial.transcript = [.agentMessage(id: "same", text: "same", timestamp: Date(timeIntervalSinceReferenceDate: 0))]
        initial.subAgents.transcripts = ["child": initial.transcript]
        let first = try prepare(initial, sequence: 1)
        var changed = initial
        changed.transcript = [.agentMessage(id: "same", text: "same", timestamp: Date(timeIntervalSinceReferenceDate: 123456789.125))]
        changed.subAgents.transcripts = ["child": changed.transcript]
        let next = try prepare(changed, sequence: 2, base: first.baseline)
        let fullBytes = try JSONEncoder().encode(envelope(changed, sequence: 2)).count
        #expect(try canonical(next.update.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(changed)))
        #expect(next.baseline.encodedByteCount == fullBytes)
        #expect(throws: SessionRuntimeConnectionError.responseTooLarge) {
            try SessionRuntimeSnapshotUpdate.prepare(envelope(changed, sequence: 2), base: first.baseline, maximumBytes: fullBytes - 1)
        }
        #expect(throws: SessionRuntimeConnectionError.responseTooLarge) {
            try next.update.restoring(base: first.baseline, maximumBytes: fullBytes - 1)
        }
    }

    /// エージェント状態カードが読む省略可能フィールドだけが変わった item も、差分として配信される。
    @Test(arguments: [
        (
            ChatItem.commandExecution(id: "c", command: "ls", output: "a", timestamp: Date(timeIntervalSince1970: 0)),
            ChatItem.commandExecution(
                id: "c", command: "ls", output: "a", timestamp: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 7), intent: "一覧を見る"
            )
        ),
        (
            ChatItem.fileChange(
                id: "f", changes: [FilePatchChange(path: "api.swift", diff: "+x", kind: nil)],
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            ChatItem.fileChange(
                id: "f", changes: [FilePatchChange(path: "api.swift", diff: "+x", kind: nil)],
                timestamp: Date(timeIntervalSince1970: 0), completedAt: Date(timeIntervalSince1970: 7)
            )
        ),
        (
            ChatItem.userMessage(id: "u", text: "直して", timestamp: Date(timeIntervalSince1970: 0), attachments: []),
            ChatItem.userMessage(
                id: "u", text: "直して", timestamp: Date(timeIntervalSince1970: 0), attachments: [],
                turnEnd: ChatTurnEnd(outcome: .completed, at: Date(timeIntervalSince1970: 7))
            )
        ),
    ])
    func changeInOnlyAStatusCardFieldIsDeliveredAsAnUpdate(before: ChatItem, after: ChatItem) throws {
        var initial = chat()
        initial.transcript = [before]
        let first = try prepare(initial, sequence: 1)
        var changed = initial
        changed.transcript = [after]

        let next = try prepare(changed, sequence: 2, base: first.baseline)

        #expect(try canonical(next.update.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(changed)))
    }

    @Test func normalizationEquivalentTextKeepsItsOriginalUTF8Bytes() throws {
        for (before, after) in [("\u{e9}", "e\u{301}"), ("a\u{301}\u{323}", "a\u{323}\u{301}")] {
            #expect(before == after)
            #expect(Array(before.utf8) != Array(after.utf8))
            var initial = chat()
            initial.transcript = [.agentMessage(id: "same", text: before, timestamp: .distantPast),
                .userMessage(id: "user", text: before, timestamp: .distantPast,
                    attachments: [.init(filename: before, mediaType: "image/png")])]
            initial.subAgents.transcripts = ["child": initial.transcript]
            initial.rawEventLog = [before]
            let first = try prepare(initial, sequence: 1)
            var changed = initial
            changed.transcript = [.agentMessage(id: "same", text: after, timestamp: .distantPast),
                .userMessage(id: "user", text: after, timestamp: .distantPast,
                    attachments: [.init(filename: after, mediaType: "image/png")])]
            changed.subAgents.transcripts = ["child": changed.transcript]
            changed.rawEventLog = [after]
            let next = try prepare(changed, sequence: 2, base: first.baseline)
            #expect(try canonical(next.update.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(changed)))
            #expect(next.baseline.encodedByteCount == (try JSONEncoder().encode(envelope(changed, sequence: 2))).count)
        }
    }

    @Test func signedZeroValuesPreserveTheirEncodedRepresentation() throws {
        let pairs: [(ChatItem, ChatItem)] = [
            (.agentMessage(id: "same", text: "same", timestamp: Date(timeIntervalSinceReferenceDate: 0.0)),
             .agentMessage(id: "same", text: "same", timestamp: Date(timeIntervalSinceReferenceDate: -0.0))),
            (.turnCost(id: "same", costUSD: 0.0, timestamp: .distantPast),
             .turnCost(id: "same", costUSD: -0.0, timestamp: .distantPast))
        ]
        for (before, after) in pairs {
            var initial = chat()
            initial.transcript = [before]
            initial.subAgents.transcripts = ["child": [before]]
            let first = try prepare(initial, sequence: 1)
            var changed = initial
            changed.transcript = [after]
            changed.subAgents.transcripts = ["child": [after]]
            let next = try prepare(changed, sequence: 2, base: first.baseline)
            #expect(try canonical(next.update.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(changed)))
            #expect(next.baseline.encodedByteCount == (try JSONEncoder().encode(envelope(changed, sequence: 2))).count)
        }
    }

    @Test func normalizationEquivalentMetadataDoesNotReuseDifferentBytes() throws {
        var initial = chat()
        initial.skillSelection = try JSONDecoder().decode(SessionRuntimeSkillSnapshot.self,
            from: Data(#"{"skills":[],"fingerprints":{},"isLoading":false,"isStale":false}"#.utf8))
        initial.skillSelection?.fingerprints = ["\u{e9}": "\u{e9}"]
        initial.skillSelection?.errorMessage = "\u{e9}"
        initial.historyEntries = [.init(sessionID: "history", preview: "\u{e9}", firstUserAt: nil,
            lastModified: .distantPast, gitBranch: nil, fileURL: URL(fileURLWithPath: "/a"))]
        initial.historySummaries = try JSONDecoder().decode([String: ChatHistorySummary].self,
            from: Data("{\"\u{e9}\":{\"messageCount\":1,\"reachesLimit\":false,\"lastMessage\":\"\u{e9}\"}}".utf8))
        let first = try prepare(initial, sequence: 1)
        var changed = initial
        changed.skillSelection?.fingerprints = ["e\u{301}": "e\u{301}"]
        changed.skillSelection?.errorMessage = "e\u{301}"
        changed.historyEntries = [.init(sessionID: "history", preview: "e\u{301}", firstUserAt: nil,
            lastModified: .distantPast, gitBranch: nil, fileURL: URL(fileURLWithPath: "/a"))]
        changed.historySummaries = try JSONDecoder().decode([String: ChatHistorySummary].self,
            from: Data("{\"e\u{301}\":{\"messageCount\":1,\"reachesLimit\":false,\"lastMessage\":\"e\u{301}\"}}".utf8))
        let next = try prepare(changed, sequence: 2, base: first.baseline)
        #expect(try canonical(next.update.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(changed)))
        #expect(next.baseline.encodedByteCount == (try JSONEncoder().encode(envelope(changed, sequence: 2))).count)
    }

    @Test func rollingRawLogDoesNotResendUnchangedHistory() throws {
        var initial = chat()
        initial.rawEventLog = (0..<500).map { "\($0):" + String(repeating: "x", count: 1536) }
        let first = try prepare(initial, sequence: 1)
        var changed = initial
        changed.transcript.append(item("tail", text: "new output"))
        changed.rawEventLog = Array(initial.rawEventLog.dropFirst()) + ["new event"]
        let next = try prepare(changed, sequence: 2, base: first.baseline)
        let fullBytes = try JSONEncoder().encode(envelope(changed, sequence: 2)).count
        #expect(try JSONEncoder().encode(next.update).count < 128 * 1024)
        #expect(try canonical(next.update.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(changed)))
        #expect(next.baseline.encodedByteCount == fullBytes)
        #expect(throws: SessionRuntimeConnectionError.responseTooLarge) {
            try next.update.restoring(base: first.baseline, maximumBytes: fullBytes - 1)
        }
    }

    @Test func rawLogChangesPreserveDuplicatesClearingAndArbitraryReplacements() throws {
        let before = ["a", "b", "a", "b"]
        for after in [before, before + ["c"], ["b", "a", "b", "c"], ["a", "b", "c"],
                      ["a", "changed", "a", "b"], [], ["new"]] {
            var initial = chat()
            initial.rawEventLog = before
            let first = try prepare(initial, sequence: 1)
            var changed = initial
            changed.rawEventLog = after
            let next = try prepare(changed, sequence: 2, base: first.baseline)
            #expect(try canonical(next.update.restoring(base: first.baseline).envelope.snapshot) == canonical(snapshot(changed)))
            #expect(next.baseline.encodedByteCount == (try JSONEncoder().encode(envelope(changed, sequence: 2))).count)
        }
        #expect(throws: SessionRuntimeConnectionError.self) {
            try RuntimeLogPatch(retainedSuffixCount: -1, appended: []).applying(to: before)
        }
        #expect(throws: SessionRuntimeConnectionError.self) {
            try RuntimeLogPatch(retainedSuffixCount: 5, appended: []).applying(to: before)
        }
    }

    private func chat() -> SessionRuntimeChatSnapshot {
        var value = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(timeIntervalSince1970: 0),
            agentRef: .builtin(.codex), workingDirectory: nil)
        value.transcript = [item("first", text: "最初"), item("second", text: "次")]
        value.rawEventLog = ["old event"]
        value.subAgents.transcripts["child"] = [item("child-first", text: "子の履歴")]
        return value
    }

    private func item(_ id: String, text: String) -> ChatItem {
        .agentMessage(id: id, text: text, timestamp: Date(timeIntervalSince1970: 0))
    }

    private func snapshot(_ chat: SessionRuntimeChatSnapshot) -> DashboardRuntimeSnapshot {
        .init(projects: [], sessions: [.chat(chat)], availableAgentKinds: [.codex])
    }

    private func envelope(_ chat: SessionRuntimeChatSnapshot, sequence: UInt64) -> SessionRuntimeSnapshotEnvelope {
        .init(sequence: sequence, snapshot: snapshot(chat))
    }

    private func prepare(_ chat: SessionRuntimeChatSnapshot, sequence: UInt64,
                         base: SessionRuntimeSnapshotBaseline? = nil) throws -> SessionRuntimePreparedSnapshot {
        try SessionRuntimeSnapshotUpdate.prepare(envelope(chat, sequence: sequence), base: base)
    }

    private func canonical(_ snapshot: DashboardRuntimeSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(snapshot)
    }
}
