import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-1（ストリーミング適用のコアレシング）の受け入れテスト。PM が著す不変の契約
// （実装役は編集禁止。ただしテストハーネスの欠陥を発見した場合は、PM に報告し承認を
// 得たうえでハーネス部分に限り修理してよい）。
//
// 契約の骨子:
// - 意味論の保存: delta の適用結果（最終 transcript）は従来と同一（項目ごとの連結・
//   初回 delta 順の項目生成・空 delta ガード）。
// - コアレシング: 短時間に連続する delta イベントは UI 無効化（transcriptRevision の
//   増分）を「イベント数 ≪ 増分」に束ねる。
// - バリア: 非 delta イベント（turnCompleted 等）を処理し終えた時点で、それ以前の
//   delta はすべて transcript に反映済み（遅延バッファの取りこぼしゼロ）。

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () async -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while await !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

@MainActor
private func makeViewModel(client: EventYieldingStructuredClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@MainActor
private func agentMessageText(_ vm: ChatSessionViewModel, id: String) -> String? {
    for item in vm.transcript {
        if case .agentMessage(let itemId, let text, _) = item, itemId == id {
            return text
        }
    }
    return nil
}

@MainActor
private func reasoningText(_ vm: ChatSessionViewModel, id: String) -> String? {
    for item in vm.transcript {
        if case .reasoning(let itemId, let text, _) = item, itemId == id {
            return text
        }
    }
    return nil
}

@MainActor
private func commandOutput(_ vm: ChatSessionViewModel, id: String) -> String? {
    for item in vm.transcript {
        if case .commandExecution(let itemId, _, let output, _) = item, itemId == id {
            return output
        }
    }
    return nil
}

// MARK: - 意味論の保存

/// バースト（200 delta）の最終 transcript は逐次適用と同一（順序どおりの連結・項目は1つ）。
@Test @MainActor
func acceptance_burstDeltas_finalTranscriptEqualsSequentialConcatenation() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    let deltas = (0..<200).map { "t\($0)|" }
    for delta in deltas {
        client.yield(.agentMessageDelta(itemId: "agent-1", delta))
    }
    let expected = deltas.joined()
    try await waitUntil { agentMessageText(vm, id: "agent-1") == expected }

    #expect(agentMessageText(vm, id: "agent-1") == expected)
    let agentItems = vm.transcript.filter {
        if case .agentMessage = $0 { return true } else { return false }
    }
    #expect(agentItems.count == 1)
}

/// 複数項目（agent / reasoning / command）へ交互に届く delta は、項目ごとに正しく連結され、
/// 項目は初回 delta の到着順で transcript に並ぶ。
@Test @MainActor
func acceptance_interleavedDeltas_perItemTextsAndCreationOrderPreserved() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.agentMessageDelta(itemId: "agent-A", "a1"))
    client.yield(.reasoningDelta(itemId: "reason-R", "r1"))
    client.yield(.agentMessageDelta(itemId: "agent-A", "a2"))
    client.yield(.commandExecution(itemId: "cmd-C", command: nil, outputDelta: "c1"))
    client.yield(.reasoningDelta(itemId: "reason-R", "r2"))
    client.yield(.commandExecution(itemId: "cmd-C", command: nil, outputDelta: "c2"))

    try await waitUntil {
        agentMessageText(vm, id: "agent-A") == "a1a2"
            && reasoningText(vm, id: "reason-R") == "r1r2"
            && commandOutput(vm, id: "cmd-C") == "c1c2"
    }
    #expect(agentMessageText(vm, id: "agent-A") == "a1a2")
    #expect(reasoningText(vm, id: "reason-R") == "r1r2")
    #expect(commandOutput(vm, id: "cmd-C") == "c1c2")

    // 初回 delta の到着順 = transcript 内の相対順（A → R → C）。
    let orderedIds = vm.transcript.map(\.id).filter {
        ["agent-A", "reason-R", "cmd-C"].contains($0)
    }
    #expect(orderedIds == ["agent-A", "reason-R", "cmd-C"])
}

/// 空 delta は項目を作らない（既存契約の回帰ガード。コアレシング導入後も保存すること）。
@Test @MainActor
func acceptance_emptyDeltaThenNonEmpty_createsSingleItemWithText() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.agentMessageDelta(itemId: "agent-1", ""))
    client.yield(.agentMessageDelta(itemId: "agent-1", "Hello"))
    try await waitUntil { agentMessageText(vm, id: "agent-1") == "Hello" }
    #expect(agentMessageText(vm, id: "agent-1") == "Hello")
}

// MARK: - バリア（非 delta イベントとの順序整合）

/// turnCompleted の処理が観測できた時点（status == .idle）で、それ以前に届いた delta は
/// すべて transcript へ反映済みであること（フラッシュ待ちの取りこぼしゼロ）。
@Test @MainActor
func acceptance_deltasFollowedByTurnCompleted_transcriptFlushedWhenIdleObserved() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    client.yield(.turnStarted)
    try await waitUntil { vm.status == .running }

    let deltas = (0..<50).map { "d\($0)|" }
    for delta in deltas {
        client.yield(.agentMessageDelta(itemId: "agent-1", delta))
    }
    client.yield(.turnCompleted(nativeSessionId: nil))

    try await waitUntil { vm.status == .idle }
    // idle を観測した「その時点」で全 delta が反映済みであること。追加の待機を挟まない。
    #expect(agentMessageText(vm, id: "agent-1") == deltas.joined())
}

// MARK: - コアレシング（UI 無効化の削減）

/// バースト（200 delta）に対する transcriptRevision の増分はイベント数より十分小さいこと。
/// （現状実装は delta 毎に +1 = +200 で red。コアレシング実装で green にする。）
@Test @MainActor
func acceptance_burstDeltas_revisionIncreaseIsCoalesced() async throws {
    let client = EventYieldingStructuredClient()
    let vm = makeViewModel(client: client)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    let revisionBefore = vm.transcriptRevision
    let deltas = (0..<200).map { "t\($0)|" }
    for delta in deltas {
        client.yield(.agentMessageDelta(itemId: "agent-1", delta))
    }
    let expected = deltas.joined()
    try await waitUntil { agentMessageText(vm, id: "agent-1") == expected }
    #expect(agentMessageText(vm, id: "agent-1") == expected)

    let revisionDelta = vm.transcriptRevision - revisionBefore
    #expect(
        revisionDelta <= 50,
        "200 delta で revision が +\(revisionDelta)。コアレシングが効いていない（イベント毎の UI 無効化）"
    )
}
