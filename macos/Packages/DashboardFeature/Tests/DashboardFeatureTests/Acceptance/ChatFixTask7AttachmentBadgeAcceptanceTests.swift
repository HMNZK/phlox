// task-7 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-7.md — 送信後のユーザーメッセージが添付メタ（ChatUserAttachment）を保持し、
// チャット画面のバッジ表示のデータ源になる。履歴 JSON は後方互換（添付フィールド欠落 → 空配列）。
// 保留中は LOOPFLOW_PENDING_TASK7=1 で suite ごとスキップできる（PM の検証運用用。実装役は使わない）。

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class Task7CaptureClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var receivedInputs: [[ChatInput]] = []

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}

    func turnStart(_ input: [ChatInput]) async throws {
        receivedInputs.append(input)
    }

    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

@Suite(
    "ChatFix task-7: 送信後のユーザーメッセージが添付メタを保持する",
    .enabled(if: ProcessInfo.processInfo.environment["LOOPFLOW_PENDING_TASK7"] != "1")
)
struct ChatFixTask7AttachmentBadgeAcceptanceTests {

    @MainActor
    private func makeViewModel(client: Task7CaptureClient) -> ChatSessionViewModel {
        ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
    }

    @Test @MainActor
    func textWithImagesSendCarriesAttachmentMetadataOnUserMessage() async throws {
        let client = Task7CaptureClient()
        let viewModel = makeViewModel(client: client)
        viewModel.attachmentStore.addImage(data: Data([1, 2, 3]), mediaType: "image/png", filename: "shot.png")
        viewModel.attachmentStore.addImage(data: Data([4, 5]), mediaType: "image/jpeg")

        try await viewModel.sendText("この画像を見て", submit: true)

        let first = try #require(viewModel.transcript.first)
        guard case let .userMessage(_, text, _, attachments) = first else {
            Issue.record("先頭アイテムが userMessage ではない: \(first)")
            return
        }
        // テキスト＋画像の同時送信でも、テキストはそのまま・添付メタが載る
        #expect(text == "この画像を見て")
        #expect(attachments.count == 2)
        #expect(attachments.map(\.mediaType) == ["image/png", "image/jpeg"])
        #expect(attachments.first?.filename == "shot.png")
    }

    @Test @MainActor
    func imageOnlySendCarriesAttachmentMetadataWithEmptyText() async throws {
        let client = Task7CaptureClient()
        let viewModel = makeViewModel(client: client)
        viewModel.attachmentStore.addImage(data: Data([1]), mediaType: "image/png")
        viewModel.attachmentStore.addImage(data: Data([2]), mediaType: "image/jpeg")

        try await viewModel.sendText("", submit: true)

        let first = try #require(viewModel.transcript.first)
        guard case let .userMessage(_, text, _, attachments) = first else {
            Issue.record("先頭アイテムが userMessage ではない: \(first)")
            return
        }
        // 画像のみ送信: 添付はバッジで可視化するため、代替文字列「（画像 N 枚）」は廃止しテキストは空のまま
        #expect(text.isEmpty)
        #expect(attachments.count == 2)
        #expect(attachments.map(\.mediaType) == ["image/png", "image/jpeg"])
    }

    // 既存トランスクリプト JSON（attachments フィールドなし）が壊れず復元できる（後方互換 decode）
    @Test
    func legacyTranscriptJSONDecodesWithEmptyAttachments() throws {
        let json = #"{"userMessage":{"id":"u1","text":"hello"}}"#
        let item = try JSONDecoder().decode(ChatItem.self, from: Data(json.utf8))
        guard case let .userMessage(id, text, _, attachments) = item else {
            Issue.record("userMessage として decode されなかった: \(item)")
            return
        }
        #expect(id == "u1")
        #expect(text == "hello")
        #expect(attachments.isEmpty)
    }

    // 添付メタが encode → decode で保存される（履歴復元後もバッジが出るための契約）
    @Test
    func attachmentMetadataRoundTripsThroughCodable() throws {
        let item = ChatItem.userMessage(
            id: "u2",
            text: "with image",
            timestamp: Date(timeIntervalSince1970: 1_752_000_000),
            attachments: [
                ChatUserAttachment(filename: "a.png", mediaType: "image/png"),
                ChatUserAttachment(filename: nil, mediaType: "image/jpeg"),
            ]
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ChatItem.self, from: data)
        // ChatItem の == は添付メタを含む（凍結）
        #expect(decoded == item)
        #expect(decoded != ChatItem.userMessage(id: "u2", text: "with image", timestamp: .distantPast))
    }
}
