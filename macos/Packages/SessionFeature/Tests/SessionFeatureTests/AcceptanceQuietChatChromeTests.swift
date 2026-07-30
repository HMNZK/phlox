import AppKit
import SwiftUI
import Testing
import AgentDomain
import DesignSystem
@testable import SessionFeature

// task-1 受け入れテスト（PM 著・不変）。アサーションは変更禁止。
@Suite("Acceptance: quiet chat chrome (task-1)")
@MainActor
struct AcceptanceQuietChatChromeTests {
    @Test("DisclosureCard は時刻・アイコン・アクセント引数なしで構築できる")
    func disclosureCardHasNoTimestampIconOrAccentArguments() {
        _ = DisclosureCard(
            isExpanded: .constant(false),
            title: "Command",
            subtitle: "実行中"
        ) { EmptyView() }
    }

    @Test("時刻は常時描画せず、発言のコピーボタンと同じホバー状態で表示する")
    func timestampsAppearOnlyWithMessageCopyButtons() throws {
        let source = try sourceText("ChatMessageCellsCommon.swift")
        let afterCardDeclaration = try #require(source.components(separatedBy: "struct DisclosureCard<Content: View>").last)
        let cardSource = try #require(afterCardDeclaration.components(separatedBy: "private struct DisclosureCardStyle").first)
        #expect(!cardSource.contains("ChatTimestampText"))
        let avatarRowSource = try #require(source.components(separatedBy: "struct AvatarMessageRow<Content: View>").last?.components(separatedBy: "struct ChatTimestampText").first)
        #expect(!avatarRowSource.contains("timestamp"))

        let basicSource = try sourceText("ChatMessageCells+Basic.swift")
        #expect(basicSource.contains("ChatTimestampText(timestamp: timestamp)"))
        #expect(basicSource.contains(".opacity(isHovering ? 1 : 0)"))
    }

    @Test("Reasoning 見出しは本文の見出し、末尾行、既定値を使う")
    func reasoningHeadlineUsesSharedThinkingRecapHeuristic() {
        #expect(ThinkingRecap.headline(from: "本文\n## 認証フローを設計\n続き") == "認証フローを設計")
        #expect(ThinkingRecap.headline(from: "最初\n最後の行") == "最後の行")
        #expect(ThinkingRecap.headline(from: "  \n ") == nil)
    }

    @Test("非表示のコピーボタンも描画サイズを保持する")
    func hiddenCopyButtonPreservesLayoutSize() throws {
        let visible = try #require(ImageRenderer(content: MessageCopyButton(
            text: "copy", accessibilityIdentifier: "visible", scale: 1, isVisible: true
        )).nsImage)
        let hidden = try #require(ImageRenderer(content: MessageCopyButton(
            text: "copy", accessibilityIdentifier: "hidden", scale: 1, isVisible: false
        )).nsImage)
        #expect(visible.size == hidden.size)
    }

    @Test("コピーボタンの背景はボタン自身のホバー時だけ表示する")
    func copyButtonBackgroundIsHoverOnly() {
        #expect(!MessageCopyButtonPresentation.showsHoverBackground(isHovering: false))
        #expect(MessageCopyButtonPresentation.showsHoverBackground(isHovering: true))
    }

    @Test("本文と見出しが同じ Reasoning は折りたたまない")
    func reasoningWithMatchingHeadlineUsesSingleLine() {
        let matching = ReasoningPresentation(text: "  認証フローを設計  ")
        let detailed = ReasoningPresentation(text: "最初の検討\n認証フローを設計\n補足")

        #expect(matching.headline == "認証フローを設計")
        #expect(!matching.usesDisclosure)
        #expect(detailed.usesDisclosure)
    }

    @Test("実行中のコマンドセルをレンダリングできる")
    func runningCommandExecutionCellRenders() throws {
        let renderer = ImageRenderer(
            content: CommandExecutionCell(
                command: "swift test",
                output: "",
                timestamp: .distantPast,
                isRunning: true
            )
            .frame(width: 320)
        )
        #expect(try #require(renderer.nsImage).size.width > 0)
    }

    @Test("本文行にブランドアバターを再導入しない")
    func avatarMessageRowSourceHasNoBrandAvatar() throws {
        let source = try sourceText("ChatMessageCellsCommon.swift")
        #expect(!source.contains("AgentBrandIcon"))
        #expect(!source.contains("AgentAvatar"))
    }

    @Test("DisclosureCard のタイトル・サブタイトル色はツールコールだけ控えめにする")
    func disclosureCardPaletteUsesRequiredColors() {
        assertColor(DisclosureCardPalette.title(isToolCall: true), equals: DSColor.chatToolCallText)
        assertColor(DisclosureCardPalette.subtitle(isToolCall: true), equals: DSColor.chatToolCallText)
        assertColor(DisclosureCardPalette.title(isToolCall: false), equals: DSColor.chatTextPrimary)
        assertColor(DisclosureCardPalette.subtitle(isToolCall: false), equals: DSColor.chatTextSecondary)
    }

    @Test("コマンドセルとコマンドグループはツールコール色を選ぶ")
    func commandCellsUseToolCallPalette() throws {
        let commandCellSource = try sourceText("ChatMessageCells+Structured.swift")
        let commandGroupSource = try sourceText("ChatMessageCells+CommandGroup.swift")
        #expect(commandCellSource.contains("isToolCall: true"))
        #expect(commandGroupSource.contains("isToolCall: true"))
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

    private func assertColor(_ actual: Color, equals expected: Color) {
        let actual = NSColor(actual).usingColorSpace(.sRGB)
        let expected = NSColor(expected).usingColorSpace(.sRGB)
        #expect(actual == expected)
    }
}
