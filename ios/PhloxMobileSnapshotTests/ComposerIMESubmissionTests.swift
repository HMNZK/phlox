import AgentDomain
import Darwin
import SwiftUI
import Testing
import UIKit
@testable import DesignSystemIOS

@MainActor
@Suite(.serialized)
struct ComposerIMESubmissionTests {
    @Observable
    fileprivate final class Draft {
        var text: String
        var cursor: Int
        var submissions: [String] = []

        init(_ text: String) {
            self.text = text
            cursor = text.utf16.count
        }
    }

    @Test(arguments: ["", "確定済み🙂 ", "[Image #1] "])
    func sendCommitsMarkedTextBeforeSubmittingAndClearsWithoutRestoring(prefix: String) async throws {
        let draft = Draft(prefix)
        let (window, editor) = try host(draft)
        defer { window.isHidden = true; window.rootViewController = nil }
        editor.setMarkedText("日本語", selectedRange: NSRange(location: 3, length: 0))
        editor.delegate?.textViewDidChange?(editor)
        try await settle(window)
        #expect(draft.text == prefix, "通常の変換中は本文を公開しない")
        #expect(editor.markedTextRange != nil)

        let button = try sendButton(in: window)
        #expect(!button.accessibilityTraits.contains(.notEnabled))
        try #require(button.accessibilityActivate())

        #expect(draft.submissions == [prefix + "日本語"])
        #expect(editor.markedTextRange == nil)
        #expect(draft.text.isEmpty)
        let deadline = ContinuousClock.now + .seconds(2)
        repeat { try await settle(window) }
        while !editor.text.isEmpty && ContinuousClock.now < deadline
        #expect(draft.text.isEmpty)
        #expect(editor.text.isEmpty, "送信前の遅延通知で本文が復元されない")
    }

    @Test
    func sendingCompositionDismissesTheKeyboard() async throws {
        let draft = Draft("前")
        let (window, editor) = try host(draft)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)
        try #require(editor.becomeFirstResponder())
        try await settle(window)
        editor.setMarkedText("日本語", selectedRange: NSRange(location: 3, length: 0))
        editor.delegate?.textViewDidChange?(editor)

        #expect(editor.text == "前日本語")
        #expect(editor.markedTextRange != nil)
        try #require(sendButton(in: window).accessibilityActivate())
        #expect(draft.submissions == ["前日本語"])
        try await settle(window)
        #expect(draft.text.isEmpty)
        #expect(editor.text.isEmpty)
        #expect(!editor.isFirstResponder, "送信後はキーボードを閉じる")
    }

    @Test(arguments: [428.0, 320.0])
    func strongPermissionControlsStayOnOneRow(width: Double) async throws {
        let draft = Draft("")
        let settings = DSInputBarSettings(
            agentName: "Claude Code",
            effortOptions: [.init(value: "high", displayName: "高")],
            selectedEffort: "high",
            permissionOptions: [.init(value: "bypassPermissions", displayName: "Bypass Permissions")],
            selectedPermission: "bypassPermissions"
        )
        let (window, _) = try host(draft, width: width, model: (.claudeCode, "Default: Opus 5.5"), settings: settings)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)
        let elements = objects(in: window)
        func frame(_ matches: (String) -> Bool) throws -> CGRect {
            try #require(elements.first { ($0.accessibilityLabel).map(matches) ?? false }).accessibilityFrame
        }
        let controls = [
            try frame { $0 == "画像を添付" },
            try frame { $0.hasPrefix("モデル、") },
            try frame { $0 == "思考の強さと権限を変更" },
            try frame { $0 == DSInputBar.sendAccessibilityLabel },
        ]
        let row = controls[0].midY
        for control in controls {
            #expect(abs(control.midY - row) < 1, "チップと送信が 1 行に並ぶ: \(controls)")
            #expect(control.minX >= 0 && control.maxX <= width, "画面からはみ出さない: \(controls)")
        }
    }

    @Test
    func sendFlushesCommittedTextWhoseDelegateDeliveryIsStillPending() async throws {
        let draft = Draft("前")
        let (window, editor) = try host(draft)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)
        editor.insertText("🙂後")
        editor.delegate?.textViewDidChange?(editor)
        try #require(sendButton(in: window).accessibilityActivate())
        #expect(draft.submissions == ["前🙂後"])
        try await settle(window)
        #expect(draft.text.isEmpty)
        #expect(editor.text.isEmpty)
    }

    @Test
    func rejectedSubmissionKeepsTheEntireCommittedDraftAndCursor() async throws {
        let draft = Draft("前")
        let (window, editor) = try host(draft, clearsOnSubmit: false)
        defer { window.isHidden = true; window.rootViewController = nil }
        editor.setMarkedText("にほんご", selectedRange: NSRange(location: 4, length: 0))
        editor.delegate?.textViewDidChange?(editor)
        try await settle(window)
        try #require(sendButton(in: window).accessibilityActivate())
        #expect(draft.submissions == ["前にほんご"])
        #expect(draft.text == "前にほんご")
        #expect(draft.cursor == draft.text.utf16.count)
        try await settle(window)
        #expect(editor.text == draft.text)
        #expect(editor.markedTextRange == nil)
    }

    @Test
    func whitespaceCompositionCannotSendThePreviousDraft() async throws {
        let draft = Draft("送らない")
        let (window, editor) = try host(draft)
        defer { window.isHidden = true; window.rootViewController = nil }
        editor.selectedRange = NSRange(location: 0, length: editor.text.utf16.count)
        editor.setMarkedText("　 ", selectedRange: NSRange(location: 2, length: 0))
        editor.delegate?.textViewDidChange?(editor)
        try await settle(window)
        let button = try sendButton(in: window)
        #expect(button.accessibilityTraits.contains(.notEnabled))
        _ = button.accessibilityActivate()
        #expect(draft.submissions.isEmpty)
        #expect(editor.text == "　 ")
    }

    @Test
    func loadingDisablesSendDuringComposition() async throws {
        let draft = Draft("前")
        let (window, editor) = try host(draft, isLoading: true)
        defer { window.isHidden = true; window.rootViewController = nil }
        editor.setMarkedText("にほんご", selectedRange: NSRange(location: 4, length: 0))
        editor.delegate?.textViewDidChange?(editor)
        try await settle(window)
        let button = try #require(objects(in: window).first { $0.accessibilityLabel == "送信中" })
        #expect(button.accessibilityTraits.contains(.notEnabled))
        _ = button.accessibilityActivate()
        #expect(draft.submissions.isEmpty)
        #expect(editor.markedTextRange != nil)
    }

    private func host(
        _ draft: Draft, clearsOnSubmit: Bool = true, isLoading: Bool = false, width: Double = 390,
        model: (kind: AgentKind, displayName: String)? = nil, settings: DSInputBarSettings? = nil
    ) throws -> (UIWindow, UITextView) {
        // shortcut: ホスト付きテストの AX 初期化は非公開 API。UIKit に公開入口ができたら置き換える。
        let library = try #require(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW))
        defer { dlclose(library) }
        let enable = try #require(dlsym(library, "_AXSSetAutomationEnabled"))
        unsafeBitCast(enable, to: (@convention(c) (Bool) -> Void).self)(true)
        let bar = DSInputBar(
            text: Binding(get: { draft.text }, set: { draft.text = $0 }),
            cursorUTF16: Binding(get: { draft.cursor }, set: { draft.cursor = $0 }),
            isLoading: isLoading,
            model: model,
            settings: settings
        ) {
            draft.submissions.append(draft.text)
            if clearsOnSubmit { draft.text = ""; draft.cursor = 0 }
        }
        let controller = UIHostingController(rootView: bar)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return (window, try #require(objects(in: window).compactMap { $0 as? UITextView }.first))
    }

    private func settle(_ window: UIWindow) async throws {
        try await Task.sleep(for: .milliseconds(80))
        window.layoutIfNeeded()
    }

    private func sendButton(in window: UIWindow) throws -> NSObject {
        let elements = objects(in: window)
        return try #require(elements.first {
            $0.accessibilityLabel == DSInputBar.sendAccessibilityLabel && $0.accessibilityTraits.contains(.button)
        })
    }

    private func objects(in root: NSObject) -> [NSObject] {
        var result: [NSObject] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            result.append(object)
            for case let child as NSObject in object.accessibilityElements ?? [] { visit(child) }
            let count = object.accessibilityElementCount()
            if count != NSNotFound && count > 0 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject { visit(child) }
                }
            }
            if let view = object as? UIView { view.subviews.forEach(visit) }
        }
        visit(root)
        return result
    }
}
