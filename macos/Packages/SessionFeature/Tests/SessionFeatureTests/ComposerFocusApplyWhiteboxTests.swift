import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SessionFeature

// task-2 白箱: IMESafeTextView がフォーカス要求を適用するときの、受け入れテストが覆っていない経路。
//   (a) 冪等性 — 同じトークンでの再描画ではフォーカスを奪い返さない（ハザード4）
//   (b) 遅延適用 — 復元本文がフォーカス要求より遅れて届いても、キャレットが本文末尾へ来る

@MainActor
private final class MutableComposerHarness {
    let window: NSWindow
    let hosting: NSHostingView<IMESafeTextView>
    let textView: NSTextView

    init(text: String) throws {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hosting = NSHostingView(rootView: MutableComposerHarness.makeView(text: text, focusRequest: .none))
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        textView = try #require(MutableComposerHarness.firstTextView(in: hosting))
    }

    static func makeView(text: String, focusRequest: ComposerFocusRequest) -> IMESafeTextView {
        IMESafeTextView(
            text: .constant(text),
            isComposing: .constant(false),
            measuredHeight: .constant(40),
            minHeight: 40,
            maxHeight: 160,
            suggestionController: nil,
            onSubmit: {},
            focusRequest: focusRequest
        )
    }

    static func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    func render(text: String, focusRequest: ComposerFocusRequest) {
        hosting.rootView = MutableComposerHarness.makeView(text: text, focusRequest: focusRequest)
        hosting.layoutSubtreeIfNeeded()
    }

    func tearDown() { window.orderOut(nil) }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    _ description: String,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("タイムアウト: \(description)")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        elapsed += 10_000_000
    }
}

@Test("同じトークンのまま再描画されても、離れたフォーカスを奪い返さない")
@MainActor
func sameTokenRerenderDoesNotReclaimFocus() async throws {
    let harness = try MutableComposerHarness(text: "本文")
    defer { harness.tearDown() }
    let request = ComposerFocusRequest(token: 1, movesCaretToEnd: false)

    harness.render(text: "本文", focusRequest: request)
    try await waitUntil("入力欄がファーストレスポンダになる") {
        harness.window.firstResponder === harness.textView
    }

    // ユーザーが別の場所（ターミナル等）へフォーカスを移した状況を作る。
    harness.window.makeFirstResponder(nil)
    #expect(harness.window.firstResponder !== harness.textView, "前提条件: フォーカスが入力欄から外れる")

    // トークンを進めずに再描画する（高さ再計算・本文以外の更新で日常的に起きる）。
    harness.render(text: "本文", focusRequest: request)
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(
        harness.window.firstResponder !== harness.textView,
        "同じ要求で二度目のフォーカス移動をしないこと。再描画のたびに奪い返すとユーザーが他所を操作できない"
    )
}

@Test("復元本文がフォーカス要求より遅れて届いても、キャレットは本文末尾へ来る")
@MainActor
func caretMovesToEndWhenTextArrivesAfterRequest() async throws {
    let harness = try MutableComposerHarness(text: "")
    defer { harness.tearDown() }
    let restored = "復元された依頼"

    // 本文がまだ空のまま、キャレット末尾指定つきの要求だけが先に届く
    // （confirmRevert は composerFocusRequest と draftRestoration を同時に更新するが、
    //  draftRestoration → draft → text binding は onChange 経由で 1 パス遅れうる）。
    harness.render(text: "", focusRequest: ComposerFocusRequest(token: 1, movesCaretToEnd: true))
    try await waitUntil("入力欄がファーストレスポンダになる") {
        harness.window.firstResponder === harness.textView
    }

    // 遅れて本文が届く（トークンは進めない）。
    harness.render(text: restored, focusRequest: ComposerFocusRequest(token: 1, movesCaretToEnd: true))

    try await waitUntil("キャレットが本文末尾へ移動する") {
        harness.textView.selectedRange() == NSRange(location: restored.utf16.count, length: 0)
    }
    #expect(
        harness.textView.selectedRange() == NSRange(location: restored.utf16.count, length: 0),
        "本文が遅れて届く順序でも、復元本文の末尾から続きを打てること"
    )
}
