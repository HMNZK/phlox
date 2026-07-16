import Foundation
import Testing
@testable import TerminalUI
@preconcurrency import SwiftTerm

private final class DumpTestTerminalDelegate: TerminalDelegate {
    func showCursor(source: Terminal) {}
    func hideCursor(source: Terminal) {}
    func setTerminalTitle(source: Terminal, title: String) {}
    func setTerminalIconTitle(source: Terminal, title: String) {}
    func windowCommand(source: Terminal, command: Terminal.WindowManipulationCommand) -> [UInt8]? { nil }
    func sizeChanged(source: Terminal) {}
    func scrolled(source: Terminal, yDisp: Int) {}
    func linefeed(source: Terminal) {}
    func bufferActivated(source: Terminal) {}
    func bell(source: Terminal) {}
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
    func cellSizeInPixels(source: Terminal) -> (width: Int, height: Int)? { nil }
}

@MainActor
@Suite struct TerminalDumpTests {
    @Test func snapshotCapturesInverseAfterIncompleteCloseWithoutSGR27() {
        let delegate = DumpTestTerminalDelegate()
        let terminal = Terminal(
            delegate: delegate,
            options: TerminalOptions(cols: 20, rows: 5, scrollback: 0)
        )
        // SGR 22 は bold 解除のみで inverse は残る (27 が必要)。ED 2J 前の cell を観測する。
        terminal.feed(text: "\u{1b}[7minverse\u{1b}[22m")

        let cells = TerminalDump.snapshot(terminal)
        let inverseTextCells = cells.filter { String($0.character) == "i" || String($0.character) == "n" }
        #expect(!inverseTextCells.isEmpty)
        #expect(inverseTextCells.contains { $0.styleDescription.contains("inverse") })
    }

    @Test func snapshotIncludesBlankCells() {
        let delegate = DumpTestTerminalDelegate()
        let terminal = Terminal(
            delegate: delegate,
            options: TerminalOptions(cols: 10, rows: 3, scrollback: 0)
        )

        let cells = TerminalDump.snapshot(terminal)
        #expect(cells.count == terminal.cols * terminal.rows)
    }

    @Test func formatProducesExpectedShape() {
        let delegate = DumpTestTerminalDelegate()
        let terminal = Terminal(
            delegate: delegate,
            options: TerminalOptions(cols: 3, rows: 2, scrollback: 0)
        )
        let cells = TerminalDump.snapshot(terminal)
        let cursor = terminal.getCursorLocation()
        let text = TerminalDump.format(
            cells,
            cols: terminal.cols,
            rows: terminal.rows,
            cursor: cursor,
            label: "test"
        )

        #expect(text.contains("r00 c00 ' ' fg=defFG bg=defBG style=[]"))
        #expect(text.contains("# label=test cols=3 rows=2"))
        #expect(text.contains("--- row0 nonBlank="))
    }

    @Test func formatWithPtyWinsize_marksMismatchNWhenSizesMatch() {
        let cells: [TerminalDump.CellSnapshot] = []
        let text = TerminalDump.format(
            cells,
            cols: 70,
            rows: 35,
            cursor: (0, 0),
            label: "test",
            ptyWinsize: (cols: 70, rows: 35)
        )

        #expect(text.contains("ptyCols=70 ptyRows=35 MISMATCH=N"))
    }

    @Test func formatWithPtyWinsize_marksMismatchYWhenSizesDiffer() {
        let cells: [TerminalDump.CellSnapshot] = []
        let text = TerminalDump.format(
            cells,
            cols: 70,
            rows: 35,
            cursor: (0, 0),
            label: "test",
            ptyWinsize: (cols: 80, rows: 24)
        )

        #expect(text.contains("ptyCols=80 ptyRows=24 MISMATCH=Y"))
    }

    @Test func write_createsFileWithGenericPrefixAndHeader() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalDumpTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cells: [TerminalDump.CellSnapshot] = []

        let file = try TerminalDump.write(
            cells,
            cols: 3,
            rows: 2,
            cursor: (1, 0),
            sessionLabel: "s1",
            label: "T0",
            to: directory
        )

        #expect(file.lastPathComponent == "terminal-dump-s1-T0.txt")
        let body = try String(contentsOf: file, encoding: .utf8)
        #expect(body.contains("# label=T0 cols=3 rows=2 cursor=(1,0)"))
    }

    @Test func write_intoMissingDirectory_createsIntermediateDirectories() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalDumpTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let nested = base.appendingPathComponent("a/b", isDirectory: true)

        let file = try TerminalDump.write(
            [],
            cols: 1,
            rows: 1,
            cursor: (0, 0),
            sessionLabel: "s2",
            label: "Spawned",
            to: nested
        )

        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func formatWithoutPtyWinsize_omitsPtyFields() {
        let cells: [TerminalDump.CellSnapshot] = []
        let text = TerminalDump.format(
            cells,
            cols: 10,
            rows: 5,
            cursor: (0, 0),
            label: "test"
        )

        #expect(!text.contains("ptyCols="))
        #expect(!text.contains("MISMATCH="))
    }
}
