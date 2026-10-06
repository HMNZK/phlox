import AppKit
import SwiftUI
import Testing
import StructuredChatKit
@testable import SessionFeature

/// UserQuestionCell を実際のウィンドウに載せて、画面に出るものを検査する。
/// 守る不具合:
/// - 秘密の質問の入力欄が平文の欄になる／回答済みカードが秘密の回答をそのまま表示する
///   （型に isSecret が乗っても View が分岐していなければ、利用者には平文のまま見える）
/// - 自由入力欄にフォーカスしても選択肢のチェックが残り、意図と違う回答が送られる
@MainActor
@Suite("UserQuestionCell: 実際に描かれた画面")
struct UserQuestionCellTests {
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
}
