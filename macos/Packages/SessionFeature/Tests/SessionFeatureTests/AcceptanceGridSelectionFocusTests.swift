import Foundation
import Testing
import AppKit
import SwiftUI
@testable import SessionFeature

// task-5 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-5.md
// 目的: (a) 注意喚起（赤枠）中でも選択状態が視認できる枠ポリシーにし、SessionGridView を
//       そのポリシー経由に配線する。(b) グリッドタイルの入力欄がキーボードフォーカスを
//       得たら、そのタイルを選択状態にする（IMESafeTextView.onFocusGained の配線）。

@Suite("Acceptance: グリッド選択の視認性とフォーカス連動（task-5）")
@MainActor
struct AcceptanceGridSelectionFocusTests {

    private func sourceText(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SessionFeature/\(relativePath)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    // MARK: - (a) 枠ポリシー

    @Test("フォーカスの視認性は注意喚起状態に関わらず保たれる")
    func focusHighlightSurvivesAttention() {
        for requiresAttention in [false, true] {
            for isFocused in [false, true] {
                let appearance = GridTileBorderPolicy.appearance(
                    isFocused: isFocused,
                    requiresAttention: requiresAttention,
                    isDropTargeted: false
                )
                #expect(
                    appearance.showsFocusHighlight == isFocused,
                    "isFocused=\(isFocused) requiresAttention=\(requiresAttention) でも選択の強調は isFocused に一致すること（赤枠が選択表示を覆い隠す現行不具合の修正）"
                )
                #expect(
                    appearance.showsAttention == requiresAttention,
                    "注意喚起の強調は requiresAttention に一致すること（選択で赤枠を消さない）"
                )
            }
        }
    }

    @Test("SessionGridView はポリシー経由で枠を決める（配線されている）")
    func sessionGridViewUsesBorderPolicy() throws {
        let source = try sourceText("SessionGridView.swift")
        #expect(
            source.contains("GridTileBorderPolicy"),
            "SessionGridView の枠決定を GridTileBorderPolicy 経由に配線すること（ポリシーだけ直してもUIに反映されない事態の防止）"
        )
    }

    // MARK: - (b) 入力欄フォーカス → 選択

    @Test("入力欄がファーストレスポンダになると onFocusGained が呼ばれる")
    func composerFocusInvokesOnFocusGained() throws {
        var focusGained = 0
        let view = IMESafeTextView(
            text: .constant(""),
            isComposing: .constant(false),
            measuredHeight: .constant(40),
            minHeight: 40,
            maxHeight: 160,
            suggestionController: nil,
            onSubmit: {},
            onFocusGained: { focusGained += 1 }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        let textView = try #require(
            firstTextView(in: hosting),
            "IMESafeTextView は NSTextView をホストしていること"
        )
        window.makeFirstResponder(textView)

        #expect(focusGained >= 1, "入力欄のフォーカス取得で onFocusGained が呼ばれること（タイル選択の起点）")

        // 後始末（ウィンドウを画面へ残さない）。
        window.orderOut(nil)
    }

    private func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    // MARK: - (b') グリッド側の配線

    @Test("グリッドタイルの composer は onFocusGained をタイル選択へ配線する")
    func gridColumnWiresFocusToSelection() throws {
        let gridSource = try sourceText("GridChatColumn.swift")
        #expect(
            gridSource.contains("onFocusGained"),
            "GridChatColumn / GridComposerBar が onFocusGained を受け取り、タイル選択（onSelect / focusedID）へ届けること"
        )
    }
}
