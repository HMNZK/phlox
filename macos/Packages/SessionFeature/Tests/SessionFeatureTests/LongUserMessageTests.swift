import AgentDomain
import AppKit
import CryptoKit
import Foundation
import StructuredChatKit
import SwiftUI
import Testing
@testable import SessionFeature

private actor LongMessageClient: StructuredAgentClient {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

@Suite("長いユーザーメッセージ", .serialized) @MainActor
struct LongUserMessageTests {
    @Test func shortMessageKeepsItsTextAndAttachmentBadge() {
        let presentation = ChatUserMessagePresentation(
            text: "画像を確認してください。",
            attachments: [ChatUserAttachment(filename: "画面.png", mediaType: "image/png")]
        )

        #expect(presentation.previewText == "画像を確認してください。")
        #expect(!presentation.isTruncated)
        #expect(presentation.showsText)
        #expect(presentation.badge?.title == "画面.png")
    }

    @Test func attachmentWithoutTextHasNoPreviewOrTruncationNotice() {
        let presentation = ChatUserMessagePresentation(
            text: "",
            attachments: [ChatUserAttachment(filename: "添付.png", mediaType: "image/png")]
        )

        #expect(presentation.previewText.isEmpty)
        #expect(!presentation.isTruncated)
        #expect(!presentation.showsText)
        #expect(presentation.badge?.title == "添付.png")
    }

    @Test func messageAtDisplayLimitIsNotMarkedAsTruncated() {
        let text = String(repeating: "あ", count: 4_096)
        let presentation = ChatUserMessagePresentation(text: text, attachments: [])

        #expect(presentation.previewText == text)
        #expect(!presentation.isTruncated)
    }

    @Test func messageOverDisplayLimitShowsOnlyThePrefix() {
        let text = String(repeating: "あ", count: 4_096) + "末"
        let presentation = ChatUserMessagePresentation(text: text, attachments: [])

        #expect(presentation.previewText == String(repeating: "あ", count: 4_096))
        #expect(presentation.isTruncated)
    }

    @Test(arguments: [
        ("a", 100_000),
        ("👨‍👩‍👧‍👦", 10_000),
        ("\u{301}", 100_000),
    ])
    func unicodeAndNewlinesCannotExpandTheDisplayBudget(unit: String, repetitions: Int) {
        let text = "a" + String(repeating: unit, count: repetitions)
        let presentation = ChatUserMessagePresentation(text: text, attachments: [])

        #expect(presentation.isTruncated)
        #expect(presentation.previewText.unicodeScalars.count == 4_096)
        #expect(!presentation.previewText.unicodeScalars.contains("\u{fffd}"))
    }

    @Test(arguments: ["\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"])
    func manyLineBreaksShowABoundedPreview(separator: String) {
        let text = String(repeating: "日本語" + separator, count: 100_000)
        let presentation = ChatUserMessagePresentation(text: text, attachments: [])

        #expect(presentation.isTruncated)
        #expect(presentation.previewText == String(repeating: "日本語" + separator, count: 31) + "日本語")
    }

    @Test func multilineMessageWithinBothLimitsStaysComplete() {
        let text = String(repeating: "日本語\n", count: 31) + "最後"
        let presentation = ChatUserMessagePresentation(text: text, attachments: [])

        #expect(!presentation.isTruncated)
        #expect(presentation.previewText == text)
    }

    @Test func fullCopyButtonIncludesTextBeyondTheVisiblePrefix() async throws {
        _ = NSApplication.shared
        let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let previous = NSApp.accessibilityAttributeValue(attribute)
        NSApp.accessibilitySetValue(true, forAttribute: attribute)
        defer { NSApp.accessibilitySetValue(previous, forAttribute: attribute) }
        let text = String(repeating: "a", count: 4_096) + "\nFULL BODY TAIL"
        let defaults = try #require(UserDefaults(suiteName: "com.phlox.tests.long-user-copy.\(UUID())"))
        let host = NSHostingView(rootView:
            UserMessageCell(text: text, timestamp: Date(timeIntervalSince1970: 1_700_000_000))
                .frame(width: 800)
                .defaultAppStorage(defaults)
        )
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        let button = try #require(await waitForFullCopyButton(in: host))

        withPreservedPasteboard { pasteboard in
            let pressed: Bool = button.accessibilityPerformPress()
            #expect(pressed)
            let copiedChangeCount = pasteboard.changeCount
            let copiedCompleteText = pasteboard.string(forType: .string) == text
            #expect(copiedCompleteText)
            return copiedChangeCount
        }
    }

    @Test func restoringAndRenderingHugeMessagePreservesTheCompleteSavedTranscript() async throws {
        let root = try artifactDirectory()
        let store = FileTranscriptStore(directoryURL: root.appendingPathComponent("transcripts"))
        let id = SessionID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let text = String(repeating: "synthetic text.\n", count: 310_000)
        let items: [ChatItem] = [
            .userMessage(id: "huge-user", text: text, timestamp: timestamp),
            .error(id: "error-1", message: "synthetic error 1", timestamp: timestamp),
            .error(id: "error-2", message: "synthetic error 2", timestamp: timestamp),
            .error(id: "error-3", message: "synthetic error 3", timestamp: timestamp),
        ]
        var metrics: [String: Double] = [:]
        let metricsURL = root.appendingPathComponent("metrics.json")
        func record(_ phase: String, since started: ContinuousClock.Instant) throws {
            let duration = started.duration(to: .now).components
            metrics[phase] = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            try JSONEncoder().encode(metrics).write(to: metricsURL, options: .atomic)
        }

        let saving = ContinuousClock.now
        try await store.replaceTranscript(for: id, with: items)
        try record("saveSeconds", since: saving)
        let file = root.appendingPathComponent("transcripts/\(id.rawValue.uuidString).json")
        let savedHash = SHA256.hash(data: try Data(contentsOf: file))

        let loading = ContinuousClock.now
        let loaded = try await store.loadTranscript(for: id)
        try record("loadSeconds", since: loading)
        #expect(loaded.map(\.id) == ["huge-user", "error-1", "error-2", "error-3"])

        let vm = ChatSessionViewModel(id: id, agentRef: .builtin(.codex), client: LongMessageClient(),
            approvalBroker: ChatApprovalBroker(), workingDirectory: root.path, transcriptStore: store)
        let restoring = ContinuousClock.now
        await vm.restore(threadId: "synthetic-long-thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        try record("restoreSeconds", since: restoring)
        #expect(vm.restoreState == .restored)
        #expect(vm.transcript.map(\.id) == ["huge-user", "error-1", "error-2", "error-3"])
        guard case .userMessage(_, let restoredText, _, _) = try #require(vm.transcript.first) else {
            Issue.record("Restoration must keep the user message")
            await vm.terminate()
            return
        }
        #expect(SHA256.hash(data: Data(restoredText.utf8)).map { String(format: "%02x", $0) }.joined() ==
            "7bc2a3ccc50e34d5fe94e17e3a9516f26fcd305e1a8f058b20467ec6d285baed")

        let rendering = ContinuousClock.now
        let size = try render(restoredText, to: root.appendingPathComponent("long-user.png"))
        try record("renderSeconds", since: rendering)
        #expect(size.width == 800)
        #expect(size.height > 100)
        #expect(size.height < 10_000)
        let shortSize = try render("README を確認してください。", to: root.appendingPathComponent("short-user.png"))
        #expect(shortSize.width == 800)
        #expect(shortSize.height < 100)

        let flushing = ContinuousClock.now
        await vm.flushTranscriptNow()
        try record("flushSeconds", since: flushing)
        #expect(SHA256.hash(data: try Data(contentsOf: file)) == savedHash)
        await vm.terminate()
    }

    private func render(_ text: String, to output: URL) throws -> CGSize {
        _ = NSApplication.shared
        let defaults = try #require(UserDefaults(suiteName: "com.phlox.tests.long-user-message.\(UUID())"))
        let view = UserMessageCell(text: text, timestamp: Date(timeIntervalSince1970: 1_700_000_000))
            .frame(width: 800)
            .defaultAppStorage(defaults)
            .environment(\.locale, Locale(identifier: "ja"))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let renderer = ImageRenderer(content: view)
        let image = try #require(renderer.nsImage)
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let png = try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        try png.write(to: output, options: .atomic)
        return size
    }

    private func waitForFullCopyButton(in host: NSView) async throws -> AnyObject? {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            if let button = fullCopyButton(in: host) { return button }
            try await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    private func fullCopyButton(in root: AnyObject) -> AnyObject? {
        if root.accessibilityIdentifier() == "ChatMessage.copyButton.user.full" { return root }
        return (root.accessibilityChildren() ?? []).lazy.compactMap { fullCopyButton(in: $0 as AnyObject) }.first
    }

    private func withPreservedPasteboard(_ action: (NSPasteboard) -> Int) {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        let copiedChangeCount = action(pasteboard)
        guard copiedChangeCount != initialChangeCount, pasteboard.changeCount == copiedChangeCount else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(saved.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        })
    }

    private func artifactDirectory() throws -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        root.appendPathComponent(".verification/long-user-message-freeze/tests/\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let owner: [String: String] = [
            "purpose": "Synthetic full transcript preservation and native rendering regression",
            "session": "long-user-message-freeze",
            "output": root.path,
            "pid": String(ProcessInfo.processInfo.processIdentifier),
            "executable": CommandLine.arguments[0],
        ]
        try JSONEncoder().encode(owner).write(to: root.appendingPathComponent("owner.json"))
        return root
    }
}
