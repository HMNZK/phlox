import AppKit
import SwiftTerm
import TerminalUI
import Testing

/// 元ファイルの代替ではなく、入力が既知の再現用ストリーム。
struct TerminalResponseTests {
    private final class Host: TerminalDelegate {
        var responses: [UInt8] = []
        func send(source: Terminal, data: ArraySlice<UInt8>) { responses.append(contentsOf: data) }
    }

    private static let sgr = [
        "1;31;44", "1;91;104", "38;5;196;48;5;21", "38:5:196;48:5:21",
        "38;2;12;34;56;48;2;78;90;123", "38:2::12:34:56;48:2::78:90:123",
        "38:2:0:12:34:56;48:2:0:78:90:123", "38:2:12:34:56;48:2:78:90:123",
        "1;4:3;38:2::12:34:56;48:2::78:90:123;22;24",
    ]

    @Test("色のCSIを全バイト境界で分割しても応答しない", arguments: sgr)
    func sgrAtEverySplit(parameters: String) {
        let bytes = Array("\u{1b}[\(parameters)mcyan 日本語\u{1b}[0m".utf8)
        for split in 0...bytes.count {
            let host = Host()
            let terminal = Terminal(delegate: host)
            terminal.feed(buffer: bytes[..<split])
            terminal.feed(buffer: bytes[split...])
            #expect(host.responses.isEmpty, "SGR=\(parameters), split=\(split)")
            #expect(terminal.getLine(row: 0)?.translateToString(trimRight: true,
                skipNullCellsFollowingWide: true, characterProvider: { terminal.getCharacter(for: $0) })
                .contains("cyan 日本語") == true)
        }
    }

    @Test("問い合わせなしの40万行の色付き出力はPTYへの応答を生成しない")
    func largeColorOutput() {
        let host = Host()
        let terminal = Terminal(delegate: host, options: TerminalOptions(cols: 80, rows: 24, scrollback: 100))
        var batch: [UInt8] = []
        for line in 0..<400_000 {
            let red = line % 256
            let green = (line / 256) % 256
            let blue = (line / 65536) % 256
            let color = line % 2 == 0
                ? "38;2;\(red);\(green);\(blue);48;2;\(blue);\(red);\(green)"
                : "38:2::\(red):\(green):\(blue);48:2::\(blue):\(red):\(green)"
            batch.append(contentsOf: "\u{1b}[1;\(30 + line % 8);\(40 + line % 8)m16\u{1b}[\(90 + line % 8);\(100 + line % 8)mbright\u{1b}[38;5;\(red);48;5;\(green)m256\u{1b}[\(color)mRGB cyan\u{1b}[0m\r\n".utf8)
            // PTYのread境界を模し、CSIの途中でも分割する。
            while batch.count >= 4093 {
                terminal.feed(buffer: batch.prefix(4093))
                batch.removeFirst(4093)
            }
        }
        terminal.feed(buffer: batch[...])
        terminal.feed(text: "prompt> ")
        #expect(host.responses.isEmpty)
        #expect(terminal.getLine(row: terminal.getCursorLocation().y)?.translateToString(trimRight: true).contains("prompt>") == true)
    }

    @Test("明示的なDA1とチェックサム問い合わせには応答する")
    func explicitQueries() {
        let host = Host()
        let terminal = Terminal(delegate: host)
        terminal.feed(text: "\u{1b}[1;0;1;1;1;1*y")
        #expect(String(bytes: host.responses, encoding: .utf8) == "\u{1b}P1!~0020\u{1b}\\")
        host.responses = []
        terminal.feed(text: "\u{1b}[c")
        #expect(String(bytes: host.responses, encoding: .utf8) == "\u{1b}[?65;4;1;2;6;21;22;17;28c")
    }

    @Test("正当な問い合わせは全バイト境界で分割しても同じ応答を返す", arguments: [
        ("\u{1b}[c", "\u{1b}[?65;4;1;2;6;21;22;17;28c"),
        ("\u{1b}[1;0;1;1;1;1*y", "\u{1b}P1!~0020\u{1b}\\"),
        // DA2の版20とDECCKSRのゼロはSwiftTermの実装値。形式はxterm仕様に従う。
        ("\u{1b}[>c", "\u{1b}[>65;20;1c"),
        ("\u{1b}[5n", "\u{1b}[0n"),
        ("\u{1b}[6n", "\u{1b}[1;1R"),
        ("\u{1b}[?63;7n", "\u{1b}P7!~0000\u{1b}\\"),
    ])
    func queriesAtEverySplit(query: String, response: String) {
        let bytes = Array(query.utf8)
        for split in 0...bytes.count {
            let host = Host()
            let terminal = Terminal(delegate: host)
            terminal.feed(buffer: bytes[..<split])
            if split < bytes.count { #expect(host.responses.isEmpty) }
            terminal.feed(buffer: bytes[split...])
            #expect(host.responses == Array(response.utf8), "query=\(query.debugDescription), split=\(split)")
        }
    }

    @Test("チェックサム問い合わせでないCSI yには応答しない", arguments: ["1y", "1;0;1;1;1;1$y", "1;0;1;1;1;1 y"])
    func nonChecksumCSI(sequence: String) {
        let host = Host()
        let terminal = Terminal(delegate: host)
        terminal.feed(text: "\u{1b}[\(sequence)")
        #expect(host.responses.isEmpty)
    }

    @Test("24bitの前景と背景を保持し、後続のSGRも適用する", arguments: [
        "38;2;12;34;56;48;2;78;90;123", "38:2::12:34:56;48:2::78:90:123",
        "38:2:0:12:34:56;48:2:0:78:90:123", "38:2:12:34:56;48:2:78:90:123",
    ])
    func trueColorAttributes(parameters: String) throws {
        let host = Host()
        let terminal = Terminal(delegate: host)
        terminal.feed(text: "\u{1b}[\(parameters);1mX\u{1b}[22;39;49mY")
        let line = try #require(terminal.getLine(row: 0))
        #expect(line[0].attribute.fg == .trueColor(red: 12, green: 34, blue: 56))
        #expect(line[0].attribute.bg == .trueColor(red: 78, green: 90, blue: 123))
        #expect(line[0].attribute.style.contains(.bold))
        #expect(line[1].attribute.fg == .defaultColor)
        // SwiftTermは背景もdefaultColorをnativeBackgroundColorへ写像する。
        // defaultInvertedColorは既定色ではなく、その反転色を表す。
        #expect(line[1].attribute.bg == .defaultColor)
        #expect(!line[1].attribute.style.contains(.bold))
        #expect(host.responses.isEmpty)
    }

    @MainActor @Test("共通端末で色付きテキストを描画する")
    func terminalRendering() throws {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data(Self.sgr.map { "\u{1b}[\($0)mColor 日本語\u{1b}[0m\r\n" }.joined().utf8))
        #expect(coordinator.visibleText().contains("Color 日本語"))
        if ProcessInfo.processInfo.environment["PHLOX_TERMINAL_SNAPSHOT"] == "1" {
            _ = NSApplication.shared
            let view = coordinator.terminalView
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 480),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.contentView = nil; window.close() }
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: image)
            let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/terminal-validation.png")
            try #require(image.representation(using: .png, properties: [:])).write(to: output)
        }
    }
}
