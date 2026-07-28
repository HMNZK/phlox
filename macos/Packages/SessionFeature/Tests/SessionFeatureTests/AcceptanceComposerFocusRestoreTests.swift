import AppKit
import Foundation
import SwiftUI
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// esc-restore-input-focus 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-1.md（ViewModel 側の発火）/ tasks/task-2.md（View 側の適用）
// 問題定義: docs/phase0.md
//   esc 2連打 → 履歴ピッカー → 過去メッセージ選択、のあと入力欄へフォーカスが戻らず、
//   マウスでクリックし直さないとタイプを再開できない。加えてキャレットが本文先頭に残るため、
//   打った文字が復元本文の前に挿入される。

// MARK: - ハーネス

private final class FocusRestoreFakeClient: StructuredAgentClient, @unchecked Sendable {
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

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ description: String,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("タイムアウト: \(description)")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

/// 2 ターン分の userMessage を積んで idle にした ViewModel を返す（リバート候補が非空になる）。
@MainActor
private func makeSeededViewModel() async throws -> (ChatSessionViewModel, FocusRestoreFakeClient) {
    let client = FocusRestoreFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-composer-focus-restore-test"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("古い依頼", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil("1ターン目が idle へ戻る") { vm.status == .idle }
    try await vm.sendText("新しい依頼", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil("2ターン目が idle へ戻る") { vm.status == .idle }
    return (vm, client)
}

/// esc 2連打でピッカーを開く（doubleEscapeWindow 内の連続呼び出し）。
@MainActor
private func openHistoryPicker(_ vm: ChatSessionViewModel) throws {
    let base = Date()
    vm.handleEscapeKey(now: base)
    vm.handleEscapeKey(now: base.addingTimeInterval(0.2))
    #expect(vm.isHistoryPickerPresented, "esc 2連打で履歴ピッカーが開くこと（前提条件）")
}

private func firstTextView(in view: NSView) -> NSTextView? {
    if let textView = view as? NSTextView { return textView }
    for subview in view.subviews {
        if let found = firstTextView(in: subview) { return found }
    }
    return nil
}

/// NSWindow + NSHostingView で IMESafeTextView をホストし、focusRequest を差し替えられるハーネス。
@MainActor
private final class ComposerFocusHarness {
    let window: NSWindow
    let hosting: NSHostingView<IMESafeTextView>
    let textView: NSTextView
    private let text: String

    init(text: String) throws {
        self.text = text
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hosting = NSHostingView(rootView: ComposerFocusHarness.makeView(text: text, focusRequest: .none))
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        textView = try #require(
            firstTextView(in: hosting),
            "IMESafeTextView は NSTextView をホストしていること"
        )
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

    func apply(_ focusRequest: ComposerFocusRequest) {
        hosting.rootView = ComposerFocusHarness.makeView(text: text, focusRequest: focusRequest)
        hosting.layoutSubtreeIfNeeded()
    }

    func tearDown() {
        window.orderOut(nil)
    }
}

private func sourceText(_ relativePath: String) throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceURL = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SessionFeature/\(relativePath)")
    return try String(contentsOf: sourceURL, encoding: .utf8)
}

// MARK: - task-1: ViewModel がフォーカス復帰を要求する

@Suite("Acceptance: esc 復元後に入力欄へフォーカスを戻す（ViewModel 側 / task-1）")
@MainActor
struct AcceptanceComposerFocusRequestTests {

    @Test("履歴を選んで復元すると、キャレット末尾指定つきでフォーカス復帰を要求する")
    func confirmRevertRequestsComposerFocusWithCaretToEnd() async throws {
        let (vm, _) = try await makeSeededViewModel()
        try openHistoryPicker(vm)
        let before = vm.composerFocusRequest
        let candidate = try #require(vm.revertCandidates.first, "リバート候補が存在すること（前提条件）")

        await vm.confirmRevert(toUserMessageID: candidate.id)

        #expect(
            vm.composerFocusRequest.token > before.token,
            "復元の完了時点でフォーカス復帰が要求されること（クリックし直さず入力を再開できるようにする）"
        )
        #expect(
            vm.composerFocusRequest.movesCaretToEnd,
            "本文を復元した経路ではキャレットを末尾へ動かすこと（先頭のままだと打った文字が復元本文の前に入る）"
        )
        #expect(vm.isHistoryPickerPresented == false, "復元でピッカーは閉じること（既存挙動の保存）")
    }

    @Test("ピッカーをキャンセルした場合もフォーカス復帰を要求する（キャレットは動かさない）")
    func cancellingPickerRequestsComposerFocus() async throws {
        let (vm, _) = try await makeSeededViewModel()
        try openHistoryPicker(vm)
        let before = vm.composerFocusRequest

        vm.handleEscapeKey()

        #expect(
            vm.composerFocusRequest.token > before.token,
            "ピッカーを閉じた経路でもフォーカスを入力欄へ返すこと（ピッカーが奪ったフォーカスの返却先を定義する）"
        )
        #expect(
            vm.composerFocusRequest.movesCaretToEnd == false,
            "本文を復元していない経路ではキャレット・選択範囲を動かさないこと"
        )
        #expect(vm.isHistoryPickerPresented == false, "キャンセルでピッカーは閉じること（既存挙動の保存）")
    }

    @Test("ピッカー非表示での単発 esc ではフォーカス復帰を要求しない")
    func singleEscapeDoesNotRequestComposerFocus() async throws {
        let (vm, _) = try await makeSeededViewModel()
        let before = vm.composerFocusRequest

        vm.handleEscapeKey()

        #expect(
            vm.composerFocusRequest == before,
            "単発 esc（中断／時刻記録のみ）はフォーカス復帰の契機ではない。誤発火は無関係な操作中にフォーカスを奪う"
        )
    }

    @Test("2連打でピッカーを開いた瞬間はフォーカス復帰を要求しない")
    func openingPickerDoesNotRequestComposerFocus() async throws {
        let (vm, _) = try await makeSeededViewModel()
        let before = vm.composerFocusRequest

        try openHistoryPicker(vm)

        #expect(
            vm.composerFocusRequest == before,
            "ピッカーを開いた直後に入力欄へフォーカスを奪うとピッカーのキーボード操作が壊れる"
        )
    }
}

// MARK: - task-2: View が要求を実際のフォーカス移動へ変換する

@Suite("Acceptance: esc 復元後に入力欄へフォーカスを戻す（View 側 / task-2）")
@MainActor
struct AcceptanceComposerFocusApplyTests {

    @Test("フォーカス要求のトークンが進むと入力欄がファーストレスポンダになる")
    func focusRequestMakesTextViewFirstResponder() async throws {
        let harness = try ComposerFocusHarness(text: "復元された依頼")
        defer { harness.tearDown() }

        harness.apply(ComposerFocusRequest(token: 1, movesCaretToEnd: false))

        try await waitUntil("入力欄がファーストレスポンダになる") {
            harness.window.firstResponder === harness.textView
        }
        #expect(
            harness.window.firstResponder === harness.textView,
            "フォーカス要求で入力欄がキーボードフォーカスを得ること（マウスでクリックし直さず入力を再開できる）"
        )
    }

    @Test("キャレット末尾指定つきの要求で、キャレットが本文末尾へ移動する")
    func focusRequestMovesCaretToEndOfText() async throws {
        let text = "復元された依頼"
        let harness = try ComposerFocusHarness(text: text)
        defer { harness.tearDown() }
        let expectedLocation = text.utf16.count
        // 実際の復元は「空の入力欄（location=0）へ本文が入る」ため、syncStringFromBinding の
        // 選択位置クランプでキャレットが先頭に残る（docs/phase0.md「キャレット位置」）。
        // その状態を再現してから要求を出す。
        harness.textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(harness.textView.selectedRange().location == 0, "前提条件: キャレットを本文先頭に置く")

        harness.apply(ComposerFocusRequest(token: 1, movesCaretToEnd: true))

        try await waitUntil("キャレットが本文末尾へ移動する") {
            harness.textView.selectedRange() == NSRange(location: expectedLocation, length: 0)
        }
        #expect(
            harness.textView.selectedRange() == NSRange(location: expectedLocation, length: 0),
            "復元本文の末尾から続きを打てること（先頭のままだと打った文字が復元本文の前に入る）"
        )
    }

    @Test("キャレット末尾指定が無い要求では、キャレット位置を動かさない")
    func focusRequestWithoutCaretMoveKeepsSelection() async throws {
        let harness = try ComposerFocusHarness(text: "復元された依頼")
        defer { harness.tearDown() }
        harness.textView.setSelectedRange(NSRange(location: 2, length: 3))

        harness.apply(ComposerFocusRequest(token: 1, movesCaretToEnd: false))

        try await waitUntil("フォーカスが入力欄へ移る") {
            harness.window.firstResponder === harness.textView
        }
        #expect(
            harness.textView.selectedRange() == NSRange(location: 2, length: 3),
            "ピッカーをキャンセルしただけの経路で選択範囲を破壊しないこと（本文は復元していない）"
        )
    }

    @Test("初回描画ではフォーカスを奪わない")
    func initialRenderDoesNotStealFocus() async throws {
        let harness = try ComposerFocusHarness(text: "")
        defer { harness.tearDown() }

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(
            harness.window.firstResponder !== harness.textView,
            "要求が無い（token == 0）あいだは入力欄がフォーカスを奪わないこと。画面を出しただけで奪うのは退行"
        )
    }

    @Test("単一表示・グリッド表示の双方が composerFocusRequest を入力欄へ配線する")
    func composerViewsWireComposerFocusRequest() throws {
        let composerSource = try sourceText("ChatComposer.swift")
        #expect(
            composerSource.contains("composerFocusRequest"),
            "ChatComposer が viewModel.composerFocusRequest を IMESafeTextView へ渡すこと"
        )
        let gridSource = try sourceText("GridChatColumn.swift")
        #expect(
            gridSource.contains("composerFocusRequest"),
            "GridChatColumn も同じ要求を渡すこと（グリッド表示でも同じ修正が要る）"
        )
    }
}
