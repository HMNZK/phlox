import AppKit
import Foundation
import SwiftTerm
import Testing
@testable import TerminalUI

@MainActor
struct TerminalRuntimeProjectionTests {
    @Test("分割UTF8とCSIの途中で接続しても次の表示を正しく受け取る")
    func partialParserSequences() throws {
        let runtime = TerminalCoordinator()
        let bytes = Array("日本語\u{1b}[31m赤\u{1b}[0m".utf8)
        for split in 1..<bytes.count {
            runtime.resetBuffer()
            runtime.feed(Data(bytes.prefix(split)))
            let gui = try TerminalCoordinator(runtimeProjection: try runtime.makeRuntimeDisplaySnapshot())
            runtime.feed(Data(bytes.dropFirst(split)))
            try gui.applyRuntimeDisplaySnapshot(try runtime.makeRuntimeDisplaySnapshot())
            #expect(gui.visibleText() == "日本語赤")
            #expect(gui.ansiScreenText() == runtime.ansiScreenText())
        }
    }

    @Test("再接続でalt画面とカーソルを復元しnormal画面への復帰も反映する")
    func alternateAndCursor() throws {
        let runtime = TerminalCoordinator()
        runtime.feed(Data("normal\u{1b}[?1049h\u{1b}[2;3H\u{1b}[44m猫\u{1b}[?25l".utf8))
        let gui = try TerminalCoordinator(runtimeProjection: try runtime.makeRuntimeDisplaySnapshot())
        #expect(gui.terminalView.getTerminal().isCurrentBufferAlternate)
        #expect(gui.terminalView.getTerminal().getCursorLocation().x == 4)
        #expect(gui.terminalView.getTerminal().getCursorLocation().y == 1)
        #expect(gui.ansiScreenText() == runtime.ansiScreenText())
        runtime.feed(Data("\u{1b}[?1049l".utf8))
        try gui.applyRuntimeDisplaySnapshot(try runtime.makeRuntimeDisplaySnapshot())
        #expect(!gui.terminalView.getTerminal().isCurrentBufferAlternate)
        #expect(gui.visibleText() == "normal")
    }

    @Test("snapshotの適用は端末問い合わせに再応答せず入力は転送する")
    func noDuplicateQueriesAndInput() async throws {
        let runtime = TerminalCoordinator()
        var replies = Data()
        runtime.onInput = { replies.append($0) }
        runtime.feed(Data("hello\u{1b}[6n\u{1b}[c".utf8))
        let gui = try TerminalCoordinator(runtimeProjection: try runtime.makeRuntimeDisplaySnapshot())
        var input = Data()
        gui.onInput = { input.append($0) }
        for _ in 0..<3 { try gui.applyRuntimeDisplaySnapshot(try runtime.makeRuntimeDisplaySnapshot()) }
        gui.feed(Data("\u{1b}[6n\u{1b}[c".utf8))
        try await Task.sleep(for: .milliseconds(20))
        #expect(!replies.isEmpty)
        #expect(input.isEmpty)
        gui.terminalView.insertText("日本語", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(20))
        #expect(input == Data("日本語".utf8))
    }

    @Test("貼付けとカーソルキーのモードを再接続後も維持する")
    func inputModes() async throws {
        let runtime = TerminalCoordinator()
        runtime.feed(Data("\u{1b}[?1h\u{1b}[?2004h\u{1b}[?1003h\u{1b}[?1006h".utf8))
        let gui = try TerminalCoordinator(runtimeProjection: try runtime.makeRuntimeDisplaySnapshot())
        #expect(gui.bracketedPasteMode)
        #expect(gui.terminalView.getTerminal().mouseMode == runtime.terminalView.getTerminal().mouseMode)
        var input = Data()
        gui.onInput = { input.append($0) }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.function, .numericPad], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\u{f702}", charactersIgnoringModifiers: "\u{f702}",
            isARepeat: false, keyCode: 123))
        gui.terminalView.keyDown(with: event)
        try await Task.sleep(for: .milliseconds(20))
        #expect(input == Data("\u{1b}OD".utf8))
    }

    @Test("サイズ変更とscrollbackを含むsnapshotはCodableで往復できる")
    func resizeAndScrollback() throws {
        let runtime = TerminalCoordinator()
        runtime.terminalView.resize(cols: 20, rows: 4)
        runtime.feed(Data((0..<20).map { "line\($0)\r\n" }.joined().utf8))
        let snapshot = try runtime.makeRuntimeDisplaySnapshot()
        let decoded = try JSONDecoder().decode(TerminalRuntimeDisplaySnapshot.self, from: JSONEncoder().encode(snapshot))
        let gui = try TerminalCoordinator(runtimeProjection: decoded)
        #expect(gui.currentCols == 20)
        #expect(gui.currentRows == 4)
        #expect(gui.ansiScreenText() == runtime.ansiScreenText())
        runtime.terminalView.resize(cols: 30, rows: 6)
        try gui.applyRuntimeDisplaySnapshot(try runtime.makeRuntimeDisplaySnapshot())
        #expect(gui.currentCols == 30)
        #expect(gui.visibleText() == runtime.visibleText())
    }

    @Test("全角と結合文字を選択でき、同じ画面の更新後も選択を保つ")
    func selectingProjectedCells() throws {
        let runtime = TerminalCoordinator()
        let text = "選択 👨‍👩‍👧‍👦 e\u{301}"
        runtime.feed(Data(text.utf8))
        let gui = try TerminalCoordinator(runtimeProjection: try runtime.makeRuntimeDisplaySnapshot())
        gui.terminalView.selectAll()
        #expect(gui.terminalView.getSelection()?.contains(text) == true)
        try gui.applyRuntimeDisplaySnapshot(try runtime.makeRuntimeDisplaySnapshot())
        #expect(gui.terminalView.getSelection()?.contains(text) == true)
    }

    @Test("切れたcellデータや上限を超える画面を黙って復元しない")
    func malformedPackedCells() throws {
        let runtime = TerminalCoordinator()
        let encoded = try JSONEncoder().encode(try runtime.makeRuntimeDisplaySnapshot())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var lines = try #require(object["lines"] as? [[String: Any]])
        lines[0]["data"] = Data([1, 2, 3]).base64EncodedString()
        object["lines"] = lines
        let malformed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TerminalRuntimeDisplaySnapshot.self, from: malformed)
        }
        runtime.terminalView.resize(cols: TerminalRuntimeDisplaySnapshot.maximumDimension + 1, rows: 2)
        #expect(throws: (any Error).self) { try runtime.makeRuntimeDisplaySnapshot() }
    }

    @Test("不正snapshotは表示を変更する前に拒否する")
    func rejectInvalidDimensions() throws {
        let runtime = TerminalCoordinator()
        runtime.feed(Data("keep".utf8))
        let snapshot = try runtime.makeRuntimeDisplaySnapshot()
        let gui = try TerminalCoordinator(runtimeProjection: snapshot)
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["columns"] = Int.max
        let invalid = try JSONDecoder().decode(TerminalRuntimeDisplaySnapshot.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(throws: (any Error).self) { try gui.applyRuntimeDisplaySnapshot(invalid) }
        #expect(gui.visibleText() == "keep")
    }
}
