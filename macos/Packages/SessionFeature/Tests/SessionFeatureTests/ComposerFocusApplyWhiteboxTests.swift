import AppKit
import Foundation
import SwiftUI
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// task-2 白箱: IMESafeTextView がフォーカス要求を適用するときの、受け入れテストが覆っていない経路。
//   (a) 冪等性 — 同じトークンでの再描画ではフォーカスを奪い返さない（ハザード4）
//   (b) 復元本文とフォーカス要求が同じ更新パスで届いたとき、キャレットが復元本文の末尾へ来る
//   (c) 実物のピッカー overlay を閉じたとき、フォーカスが composer へ戻る（負の対照つき）

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

@Test("復元前の下書きより長い本文へ置き換わっても、キャレットは復元本文の末尾へ来る")
@MainActor
func caretMovesToEndOfRestoredTextReplacingShorterDraft() async throws {
    let harness = try MutableComposerHarness(text: "短")
    defer { harness.tearDown() }
    harness.textView.setSelectedRange(NSRange(location: 0, length: 0))

    // confirmRevert は draft とフォーカス要求を同じ代入で確定させるので、View にも同じ更新パスで届く。
    // このとき本文同期（syncStringFromBinding）は旧選択位置をクランプ保持するだけなので、
    // 末尾化がなければ復元本文の途中にキャレットが残る。
    let restored = "復元された長い本文"
    harness.render(text: restored, focusRequest: ComposerFocusRequest(token: 1, movesCaretToEnd: true))

    try await waitUntil("キャレットが復元本文の末尾へ移動する") {
        harness.textView.selectedRange() == NSRange(location: restored.utf16.count, length: 0)
    }
    #expect(
        harness.textView.selectedRange() == NSRange(location: restored.utf16.count, length: 0),
        "復元本文の末尾から続きを打てること（旧下書きの長さでクランプされて途中に残らない）"
    )
}

// MARK: - ピッカー overlay との競合（レビュー指摘 HIGH）

/// 実物の `ChatHistoryRevertPicker` overlay（`.chatEscapeHandling`）と composer を同じウィンドウに載せ、
/// 「ピッカーが奪ったフォーカスが、閉じたあと composer へ戻るか」を実測するハーネス。
/// 受け入れテストは composer 単体しかホストしていないため、overlay 除去とフォーカス移動の順序を覆えない。
private struct FocusRaceHarnessView: View {
    let viewModel: ChatSessionViewModel
    /// false にすると focusRequest を配線しない＝修正前の状態を再現する（負の対照実験用）。
    let wiresFocusRequest: Bool
    @State private var text = ""
    @State private var isComposing = false
    @State private var height: CGFloat = 40

    var body: some View {
        IMESafeTextView(
            text: $text,
            isComposing: $isComposing,
            measuredHeight: $height,
            minHeight: 40,
            maxHeight: 160,
            suggestionController: nil,
            onSubmit: {},
            focusRequest: wiresFocusRequest ? viewModel.composerFocusRequest : .none
        )
        .frame(width: 400, height: 60)
        .chatEscapeHandling(viewModel: viewModel)
    }
}

/// ピッカーを開いた状態のハーネスを組み立てて返す。前提条件（composer→ピッカーへフォーカスが移る）
/// はここで確認するので、呼び出し側は「閉じたあとどうなるか」だけを見ればよい。
@MainActor
private func makeOpenedPickerHarness(
    wiresFocusRequest: Bool
) async throws -> (vm: ChatSessionViewModel, window: NSWindow, hosting: NSView, textView: NSTextView) {
    let client = RaceFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-composer-focus-race-test"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("古い依頼", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil("idle へ戻る") { vm.status == .idle }

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let hosting = NSHostingView(
        rootView: FocusRaceHarnessView(viewModel: vm, wiresFocusRequest: wiresFocusRequest)
    )
    hosting.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()

    let textView = try #require(MutableComposerHarness.firstTextView(in: hosting))
    window.makeFirstResponder(textView)
    try #require(window.firstResponder === textView, "前提条件: まず composer にフォーカスがある")

    // esc 2連打でピッカーを開く。ピッカーは .focused() で自らフォーカスを取る。
    let base = Date()
    vm.handleEscapeKey(now: base)
    vm.handleEscapeKey(now: base.addingTimeInterval(0.2))
    try #require(vm.isHistoryPickerPresented, "前提条件: ピッカーが開く")
    hosting.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 300_000_000)
    // ここが本テストの成立条件。ピッカーが実際にフォーカスを奪っていなければ、
    // 「閉じたら戻る」の検証は何も証明しない（composer が最初から持ったままなので必ず通る）。
    try #require(
        window.firstResponder !== textView,
        "前提条件: ピッカーが composer からキーボードフォーカスを奪っている"
    )
    return (vm, window, hosting, textView)
}

private final class RaceFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func resetConversation() async {}
    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

@Test("履歴ピッカーを閉じると、overlay の退場アニメーション完了後も composer がフォーカスを持つ")
@MainActor
func closingRealPickerReturnsFocusToComposer() async throws {
    let harness = try await makeOpenedPickerHarness(wiresFocusRequest: true)
    defer { harness.window.orderOut(nil) }

    // ピッカーを閉じる（キャンセル経路）。ここでフォーカス復帰要求が発火する。
    harness.vm.handleEscapeKey()
    harness.hosting.layoutSubtreeIfNeeded()

    try await waitUntil(timeoutNanoseconds: 3_000_000_000, "composer へフォーカスが戻る") {
        harness.window.firstResponder === harness.textView
    }

    // ChatEscapeHandling の overlay は .easeOut(duration: 0.15) で退場する。
    // 「一度は戻ったがアニメーション完了時に奪い返される」ことがないよう、完了後にもう一度見る。
    try await Task.sleep(nanoseconds: 250_000_000)
    #expect(
        harness.window.firstResponder === harness.textView,
        "overlay の退場が完了したあとも composer がキーボードフォーカスを保つこと"
    )
}

@Test("負の対照: focusRequest を配線しないと、ピッカーを閉じてもフォーカスは composer へ戻らない")
@MainActor
func withoutWiringFocusDoesNotReturnToComposer() async throws {
    let harness = try await makeOpenedPickerHarness(wiresFocusRequest: false)
    defer { harness.window.orderOut(nil) }

    harness.vm.handleEscapeKey()
    harness.hosting.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 500_000_000)

    #expect(
        harness.window.firstResponder !== harness.textView,
        "修正前は composer にフォーカスが戻らないこと。このテストが赤くなる（配線が無くても戻る）なら、上の正のテストは何も証明していない"
    )
}

// MARK: - IME 変換中の保護

@Test("IME 変換中はキャレットを末尾へ動かさない（変換途中の確定位置を壊さない）")
@MainActor
func caretIsNotMovedWhileComposing() throws {
    let parent = MutableComposerHarness.makeView(text: "復元本文", focusRequest: .none)
    let coordinator = IMESafeTextView.Coordinator(parent)
    let textView = IMESafeTextView.SubmitAwareTextView()
    textView.string = "復元本文"
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.setMarkedText(
        "へんかん",
        selectedRange: NSRange(location: 0, length: 0),
        replacementRange: NSRange(location: 0, length: 0)
    )
    try #require(textView.hasMarkedText(), "前提条件: IME 変換中の状態を作る")
    let duringComposing = textView.selectedRange()

    coordinator.moveCaretToEnd(of: textView)

    #expect(
        textView.selectedRange() == duringComposing,
        "変換中の選択位置を末尾化で壊さないこと"
    )
}
