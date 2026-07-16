// task-8 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-8.md — composer の画像添付（＋ボタン・ペースト）とファイル参照。

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private let tinyPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

@Test @MainActor
func composerAttachment_store_addsWithinLimits() {
    let store = ComposerAttachmentStore()
    store.addImage(data: tinyPNG, mediaType: "image/png", filename: "a.png")
    #expect(store.attachments.count == 1)
    #expect(store.attachments.first?.mediaType == "image/png")
    #expect(store.lastError == nil)
}

@Test @MainActor
func composerAttachment_store_rejectsOversizedImage() {
    let store = ComposerAttachmentStore()
    let oversized = Data(count: ComposerAttachmentStore.maxBytesPerImage + 1)
    store.addImage(data: oversized, mediaType: "image/png")
    #expect(store.attachments.isEmpty)
    #expect(store.lastError != nil)
}

@Test @MainActor
func composerAttachment_store_rejectsFifthImage() {
    let store = ComposerAttachmentStore()
    for i in 0..<4 {
        store.addImage(data: tinyPNG, mediaType: "image/png", filename: "img\(i).png")
    }
    #expect(store.attachments.count == 4)
    store.addImage(data: tinyPNG, mediaType: "image/png", filename: "img4.png")
    #expect(store.attachments.count == 4)
    #expect(store.lastError != nil)
}

@Test @MainActor
func composerAttachment_store_removeAndClear() throws {
    let store = ComposerAttachmentStore()
    store.addImage(data: tinyPNG, mediaType: "image/png")
    store.addImage(data: tinyPNG, mediaType: "image/jpeg")
    let first = try #require(store.attachments.first)
    store.remove(id: first.id)
    #expect(store.attachments.map(\.mediaType) == ["image/jpeg"])
    store.clear()
    #expect(store.attachments.isEmpty)
}

@Test @MainActor
func composerAttachment_store_fileReferenceReturnsAtPath() {
    let store = ComposerAttachmentStore()
    #expect(store.addFileReference(path: "Packages/Foo/Bar.swift") == "@Packages/Foo/Bar.swift")
    #expect(store.attachments.isEmpty)
}

// MARK: - ViewModel の送信入力組み立て

private final class AttachmentFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

@Test @MainActor
func composerAttachment_buildChatInputs_combinesTextAndImages() {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: AttachmentFakeClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    vm.attachmentStore.addImage(data: tinyPNG, mediaType: "image/png")

    let withText = vm.buildChatInputs(text: "説明して")
    #expect(withText == [
        .text("説明して"),
        .image(data: tinyPNG, mediaType: "image/png"),
    ])

    let imageOnly = vm.buildChatInputs(text: "")
    #expect(imageOnly == [.image(data: tinyPNG, mediaType: "image/png")])
}
