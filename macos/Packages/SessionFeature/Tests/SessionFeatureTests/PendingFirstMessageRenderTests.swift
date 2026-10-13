import AgentDomain
import AppKit
import Foundation
import StructuredChatKit
import SwiftUI
import Testing
import Vision
@testable import SessionFeature

/// 要件 E5: 起動中に預かった初回メッセージにだけ「送信待ち」を添える。
@Suite("起動中の初回メッセージ", .serialized) @MainActor
struct PendingFirstMessageRenderTests {
    @Test func onlyPendingFirstMessageShowsWaitingCaption() throws {
        let pending = ChatItem.userMessage(
            id: "\(ChatSessionViewModel.pendingFirstMessageIDPrefix)\(UUID().uuidString)",
            text: "README を確認してください", timestamp: Date(), attachments: []
        )
        let sent = ChatItem.userMessage(id: "user-1", text: "README を確認してください", timestamp: Date(), attachments: [])

        #expect(try recognizedText(pending).contains("起動が終わると送ります"))
        #expect(!(try recognizedText(sent).contains("起動が終わると送ります")))
    }

    private func recognizedText(_ item: ChatItem) throws -> String {
        let view = ChatItemView(item: item, isRunningCommand: false, agentDescriptor: AgentRegistry.descriptor(for: .claudeCode))
            .frame(width: 520, height: 160)
            .environment(\.locale, Locale(identifier: "ja"))
            .environment(\.colorScheme, .dark)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}
