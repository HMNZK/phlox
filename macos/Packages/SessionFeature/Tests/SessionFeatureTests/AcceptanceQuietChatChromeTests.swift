import AppKit
import SwiftUI
import Testing
import DesignSystem
@testable import SessionFeature

// task-1 受け入れテスト（PM 著・不変）。アサーションは変更禁止。
@Suite("Acceptance: quiet chat chrome (task-1)")
@MainActor
struct AcceptanceQuietChatChromeTests {
    @Test("DisclosureCard はアイコン・アクセント引数なしで構築できる")
    func disclosureCardHasNoIconOrAccentArguments() {
        _ = DisclosureCard(
            isExpanded: .constant(false),
            title: "Command",
            subtitle: "実行中",
            timestamp: .distantPast
        ) { EmptyView() }
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
