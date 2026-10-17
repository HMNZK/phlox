import AppKit
import SwiftUI
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

/// UserQuestionCell を実際のウィンドウに載せて、画面に出るものを検査する。
/// 守る不具合:
/// - 秘密の質問の入力欄が平文の欄になる／回答済みカードが秘密の回答をそのまま表示する
///   （型に isSecret が乗っても View が分岐していなければ、利用者には平文のまま見える）
/// - 自由入力欄にフォーカスしても選択肢のチェックが残り、意図と違う回答が送られる
/// - 自由入力欄で 1〜9 を打つとカードの選択に横取りされ、数字が入らない
@MainActor
@Suite("UserQuestionCell: 実際に描かれた画面")
struct UserQuestionCellTests {
    @Test(arguments: [CGFloat(320), 500, 900], [1, 4])
    func 長い質問と選択肢は全体をスクロールでき送信ボタンは枠内に残る(width: CGFloat, count: Int) throws {
        let questions = (0..<count).map { index in
            ChatUserQuestion(
                question: "質問 \(index): " + String(repeating: "長い質問の本文を最後まで読めることを確認します。", count: 30),
                header: "質問 \(index)",
                options: (0..<8).map { ChatUserQuestionOption(label: "選択肢 \($0)", description: "選択肢の説明です。") },
                multiSelect: false, id: "q\(index)"
            )
        }
        let cell = UserQuestionCell(
            itemId: "long", requestId: "r", questions: questions, answers: nil,
            state: .pending, timestamp: Date(), onRespond: { _, _ in true }, onDismiss: {}
        ).environment(\.replySubjectMaxHeight, 160)
        let hosting = NSHostingView(rootView: cell)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        let scrolls = scrollViews(in: hosting)
        let scroll = try #require(scrolls.first { ($0.documentView?.frame.height ?? 0) > $0.contentSize.height })
        // 本文だけのスクロールでは、選択肢と複数の質問がカードを画面外へ押し出す。
        #expect(scrolls.count == 1)
        #expect(scroll.frame.height <= 160.5)
        #expect(hosting.fittingSize.height <= 220)
        let document = try #require(scroll.documentView)
        let start = scroll.contentView.bounds.origin
        let endY = document.bounds.maxY - scroll.contentSize.height
        scroll.contentView.scroll(to: CGPoint(x: 0, y: endY))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.origin.y > start.y)
        scroll.contentView.scroll(to: start)
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(abs(scroll.contentView.bounds.origin.y - start.y) < 1)
    }

    @Test func 短い質問は高さ上限まで引き伸ばさない() {
        let previous = NSApplication.shared.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        defer { NSApplication.shared.accessibilitySetValue(previous, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")) }
        let hosted = host(question(isSecret: false))
        defer { hosted.window.close() }
        #expect(hosted.hosting.fittingSize.height < 200)
    }

    @Test(arguments: [false, true], [CGFloat(320), 600])
    func 単体とグリッドで質問の先頭と末尾と操作ボタンへ到達できる(grid: Bool, width: CGFloat) async throws {
        let previous = NSApplication.shared.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        defer { NSApplication.shared.accessibilitySetValue(previous, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")) }
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let client = LayoutQuestionClient()
        let vm = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.claudeCode), client: client,
                                      approvalBroker: ChatApprovalBroker(), workingDirectory: FileManager.default.currentDirectoryPath)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        let questions = (0..<4).map { index in
            ChatUserQuestion(question: "質問 \(index): " + String(repeating: "質問の説明が長くても最後まで読めます。", count: 8),
                             header: "確認 \(index)", options: (0..<5).map { ChatUserQuestionOption(label: "候補 \(index)-\($0)") },
                             multiSelect: false, id: "q\(index)")
        }
        client.continuation.yield(.userQuestionRequested(requestId: "layout", questions: questions))
        for _ in 0..<100 where !ChatReplyArea<EmptyView>.hasPendingQuestion(in: vm.transcript) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ChatReplyArea<EmptyView>.hasPendingQuestion(in: vm.transcript))
        let surface = grid ? AnyView(GridChatColumn(viewModel: vm, onFocusGained: {})) : AnyView(ChatSessionView(viewModel: vm))
        let hosting = NSHostingView(rootView: surface.environment(\.locale, Locale(identifier: "ja_JP")))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: width, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }

        func elements(_ object: AnyObject) -> [AnyObject] {
            [object] + (object.accessibilityChildren() ?? []).flatMap { elements($0 as AnyObject) }
        }
        let buttons = elements(hosting).filter { $0.accessibilityRole() == .button }
        let send = try #require(buttons.first { ($0.accessibilityLabel() ?? "").hasPrefix("回答を送信") })
        let close = try #require(buttons.first { ($0.accessibilityLabel() ?? "") == "回答せずに閉じる" })
        let windowFrame = window.convertToScreen(hosting.bounds)
        for button in [send, close] {
            #expect(windowFrame.contains(button.accessibilityFrame()), "操作ボタンが会話欄からはみ出している")
        }

        func allScrollViews(_ view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(allScrollViews)
        }
        // 質問カードは入力欄の手前にある最後の、縦にあふれるスクロール領域。
        let scroll = try #require(allScrollViews(hosting).last { ($0.documentView?.frame.height ?? 0) > $0.contentSize.height })
        #expect(scroll.frame.height <= ApprovalCard.subjectMaxHeight(availableHeight: 480) + 1)
        #expect(hosting.bounds.contains(scroll.convert(scroll.bounds, to: hosting)))
        let document = try #require(scroll.documentView)
        let first = scroll.contentView.bounds.origin
        try snapshot(hosting, name: "\(grid ? "grid" : "single")-\(Int(width))-top")
        scroll.contentView.scroll(to: CGPoint(x: 0, y: document.bounds.maxY - scroll.contentSize.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        hosting.layoutSubtreeIfNeeded()
        #expect(scroll.contentView.bounds.origin.y > first.y)
        let lastField = try #require(elements(hosting).last { ($0.accessibilityIdentifier() ?? "") == "UserQuestionCell.freeText.q3" })
        let viewport = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
        #expect(viewport.contains(lastField.accessibilityFrame()), "末尾の自由入力欄へ到達できない")
        for button in [send, close] {
            #expect(windowFrame.contains(button.accessibilityFrame()), "スクロール後に操作ボタンが見切れている")
        }
        try snapshot(hosting, name: "\(grid ? "grid" : "single")-\(Int(width))-bottom")
        scroll.contentView.scroll(to: first)
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(abs(scroll.contentView.bounds.origin.y - first.y) < 1)
        await vm.terminate()
    }

    private func snapshot(_ hosting: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["PHLOX_QUESTION_SNAPSHOTS"] else { return }
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }

    private struct Hosted {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>

        /// 画面に出ているテキスト（アクセシビリティの静的テキストとボタンの名前。選択肢と回答済みの行はボタン）。
        var texts: [String] {
            var result: [String] = []
            func visit(_ object: AnyObject) {
                if object.accessibilityRole() == .staticText, let value = object.accessibilityValue() { result.append(value) }
                if object.accessibilityRole() == .button, let label = object.accessibilityLabel() { result.append(label) }
                for child in object.accessibilityChildren() ?? [] { visit(child as AnyObject) }
            }
            visit(hosting)
            return result
        }

        func button(named prefix: String) -> AnyObject? {
            func visit(_ object: AnyObject) -> AnyObject? {
                if object.accessibilityRole() == .button, (object.accessibilityLabel() ?? "").hasPrefix(prefix) { return object }
                for child in object.accessibilityChildren() ?? [] { if let found = visit(child as AnyObject) { return found } }
                return nil
            }
            return visit(hosting)
        }

        func textFields() -> [NSTextField] {
            var result: [NSTextField] = []
            func visit(_ view: NSView) {
                // SwiftUI が入力欄として載せる AppKitTextField / AppKitSecureTextField（ラベル用の内部ビューは除く）。
                if let field = view as? NSTextField, view.className.contains(".AppKit") { result.append(field) }
                view.subviews.forEach(visit)
            }
            visit(hosting)
            return result
        }

        func settle() { hosting.layoutSubtreeIfNeeded() }
    }

    private func host(
        _ question: ChatUserQuestion,
        state: ChatUserQuestionState = .pending,
        answers: [String: [String]]? = nil,
        placement: UserQuestionCell.Placement = .replyArea
    ) -> Hosted {
        // SwiftUI のアクセシビリティ木は、支援技術が有効なときだけ作られる。
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let cell = UserQuestionCell(
            itemId: "i", requestId: "r", questions: [question], answers: answers,
            state: state, timestamp: Date(), onRespond: { _, _ in true }, placement: placement
        )
        let hosting = NSHostingView(rootView: AnyView(cell.environment(\.locale, Locale(identifier: "ja_JP"))))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = CGRect(x: 0, y: 0, width: 500, height: 400)
        let hosted = Hosted(window: window, hosting: hosting)
        hosted.settle()
        return hosted
    }

    private func question(isSecret: Bool, options: [String] = []) -> ChatUserQuestion {
        ChatUserQuestion(
            question: "API キーは？", header: "認証",
            options: options.map { ChatUserQuestionOption(label: $0) },
            multiSelect: false, id: "q1", isSecret: isSecret
        )
    }

    // MARK: - 秘密の回答

    @Test func 秘密の質問の自由入力欄は伏せ字の欄になる() {
        let secret = host(question(isSecret: true))
        #expect(secret.textFields().contains { $0 is NSSecureTextField }, "isSecret の入力欄が SecureField になっていない")

        let plain = host(question(isSecret: false))
        #expect(!plain.textFields().isEmpty)
        #expect(!plain.textFields().contains { $0 is NSSecureTextField }, "秘密でない質問の入力欄が伏せ字になっている")
    }

    @Test(arguments: [UserQuestionCell.Placement.replyArea, .transcript])
    func 回答済みカードは秘密の回答を伏せ字で表示し平文を出さない(placement: UserQuestionCell.Placement) {
        let secret = host(question(isSecret: true), state: .answered, answers: ["q1": ["api-key-123"]], placement: placement)
        let secretText = secret.texts.joined(separator: "\n")
        #expect(secretText.contains(UserQuestionAnswerDisplay.secretMask), "伏せ字が表示されていない: \(secretText)")
        #expect(!secretText.contains("api-key-123"), "秘密の回答が平文で表示されている")

        // 対照: 秘密でない回答はそのまま出る（上の検査が「何も表示していない」で通らないことの裏づけ）。
        let plain = host(question(isSecret: false), state: .answered, answers: ["q1": ["api-key-123"]], placement: placement)
        #expect(plain.texts.joined(separator: "\n").contains("api-key-123"))
    }

    // MARK: - 自由入力欄のフォーカス

    @Test func 自由入力欄にフォーカスすると選んでいた選択肢が外れ送信できなくなる() throws {
        let hosted = host(question(isSecret: false, options: ["A", "B"]))
        let optionA = try #require(hosted.button(named: "A"))
        let pressed = optionA.accessibilityPerformPress()
        hosted.settle()
        #expect(pressed)
        let selectedBefore = optionA.isAccessibilitySelected()
        #expect(selectedBefore, "前提: 選択肢 A が選ばれる")
        let submitBefore = try #require(hosted.button(named: "回答を送信"))
        let canSubmitBefore = submitBefore.isAccessibilityEnabled()
        #expect(canSubmitBefore, "前提: 選択すると送信できる")

        let field = try #require(hosted.textFields().first)
        let focused = hosted.window.makeFirstResponder(field)
        hosted.settle()
        #expect(focused)

        let optionAAfter = try #require(hosted.button(named: "A"))
        let selectedAfter = optionAAfter.isAccessibilitySelected()
        #expect(!selectedAfter, "自由入力欄にフォーカスしても選択肢のチェックが残っている（表示と送られる回答がずれる）")
        let submitAfter = try #require(hosted.button(named: "回答を送信"))
        let canSubmitAfter = submitAfter.isAccessibilityEnabled()
        #expect(!canSubmitAfter, "選択が外れたのに送信できてしまう")
    }

    // MARK: - 数字キー

    @Test func 自由入力欄では数字キーが文字として入る() throws {
        let hosted = host(question(isSecret: false, options: ["A", "B"]))
        let field = try #require(hosted.textFields().first)
        #expect(hosted.window.makeFirstResponder(field))
        hosted.settle()
        for character in ["1", "2", "0"] {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: hosted.window.windowNumber, context: nil,
                characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0
            ))
            hosted.window.sendEvent(event)
        }
        hosted.settle()
        let editor = hosted.window.fieldEditor(false, for: field)
        let typed = editor?.string ?? field.stringValue
        #expect(typed == "120", "自由入力欄で数字が入らない（カードの 1〜9 の選択に横取りされる）: \(typed)")
    }
}

private struct LayoutQuestionClient: StructuredAgentClient {
    let events: AsyncStream<NormalizedChatEvent>
    let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() { (events, continuation) = AsyncStream.makeStream() }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}
