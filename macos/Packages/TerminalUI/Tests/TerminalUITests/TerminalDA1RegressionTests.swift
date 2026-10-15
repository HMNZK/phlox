import CryptoKit
import SwiftTerm
import Testing

struct TerminalDA1RegressionTests {
    private final class Host: TerminalDelegate {
        var responses: [UInt8] = []
        func send(source: Terminal, data: ArraySlice<UInt8>) { responses.append(contentsOf: data) }
    }

    // /tmp/phlox-orch/gen-colors.py と同じ決定的な入力。random は生成に使われていない。
    private static let colorFile: [UInt8] = {
        let words = ["drwxr-xr-x", "-rw-r--r--", "ryosuke", "staff", "Oct", "15", "17:20",
                     "README.md", "Package.swift", "Sources", "Tests", "build.log", "main.swift", "image.png", "archive.tar.gz"]
        var bytes: [UInt8] = []
        bytes.reserveCapacity(50 * 1024 * 1024 + 256)
        var i = 0
        while bytes.count <= 50 * 1024 * 1024 {
            let word = words[i % 15]
            let number = String(i)
            let line = "\u{1b}[1;\(31 + i % 7)m\(word)\(String(repeating: " ", count: max(0, 12 - word.count)))\u{1b}[0m "
                + "\u{1b}[\(90 + (i * 3) % 8)m\(String(repeating: " ", count: max(0, 9 - number.count)))\(number)\u{1b}[0m "
                + "\u{1b}[38;5;\(i % 256)m\(words[(i * 7) % 15])\u{1b}[0m "
                + "\u{1b}[\(40 + (i * 5) % 8);97m \(words[(i * 11) % 15]) \u{1b}[0m "
                + "\u{1b}[38;2;\(i % 256);\((i * 3) % 256);\((i * 7) % 256)mtruecolor-\(i)\u{1b}[0m\n"
            bytes.append(contentsOf: line.utf8)
            i += 1
        }
        return bytes
    }()

    @Test("生成スクリプトと同じバイト列を使う")
    func fixtureMatchesRecordedFile() {
        let bytes = Self.colorFile
        #expect(bytes.count == 52_428_835)
        #expect(bytes.filter { $0 == 10 }.count == 409_782)
        #expect(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            == "b943e35898a07e505f3d39b159453a8f2be4a517e0ee16e036773547f27a39a7")
    }

    @Test("実機と同じ52MBのSGR出力を4KB前後で分割しても応答しない",
          arguments: [4093, 4095, 4096], [false, true])
    func recordedColorFile(chunkSize: Int, onlcr: Bool) throws {
        // interactive PTY の ONLCR による LF → CRLF も検査する。
        let bytes = onlcr ? Self.colorFile.flatMap { $0 == 10 ? [UInt8(13), 10] : [$0] } : Self.colorFile
        let host = Host()
        let terminal = Terminal(delegate: host, options: TerminalOptions(cols: 80, rows: 24, scrollback: 100))
        for start in stride(from: 0, to: bytes.count, by: chunkSize) {
            let end = min(start + chunkSize, bytes.count)
            // PTY → Data → Coordinator と同じく、各チャンクの添字を0から始める。
            terminal.feed(byteArray: Array(bytes[start..<end]))
            try #require(host.responses.isEmpty,
                "ONLCR=\(onlcr), chunk=\(start)..<\(end), response=\(String(bytes: host.responses, encoding: .utf8).debugDescription), input=\(String(bytes: bytes[max(0, start - 80)..<min(end + 80, bytes.count)], encoding: .utf8).debugDescription)")
        }
    }

    @Test("4KB出力の滞留による破棄はSGRの途中をDA1問い合わせへ接続する")
    func droppedChunksCreateDA1Query() async {
        let bytes = Self.colorFile
        let host = Host()
        let terminal = Terminal(delegate: host, options: TerminalOptions(cols: 80, rows: 24, scrollback: 100))
        let chunkSize = 4096
        let prefixEnd = 49_152
        for start in stride(from: 0, to: prefixEnd, by: chunkSize) {
            terminal.feed(buffer: bytes[start..<(start + chunkSize)])
        }
        // 修正前の PTYManager / UserTerminalController と同じ容量・破棄方針（現在は .unbounded。ADR 0212）。
        let (stream, continuation) = AsyncStream<ArraySlice<UInt8>>.makeStream(bufferingPolicy: .bufferingNewest(2048))
        var dropped = 0
        for start in stride(from: prefixEnd, to: prefixEnd + (2048 + 55) * chunkSize, by: chunkSize) {
            if case .dropped = continuation.yield(bytes[start..<(start + chunkSize)]) { dropped += 1 }
        }
        continuation.finish()
        #expect(dropped == 55)
        // 欠落前の末尾 ESC [ と、欠落後の通常文字 c が、実際の問い合わせ ESC [ c になる。
        #expect(Array(bytes[(prefixEnd - 2)..<prefixEnd]) == [0x1b, 0x5b])
        #expect(bytes[prefixEnd + dropped * chunkSize] == 0x63)
        for await chunk in stream { terminal.feed(buffer: chunk) }
        #expect(host.responses == Array("\u{1b}[?65;4;1;2;6;21;22;17;28c".utf8))
    }

    @Test("実PTYで観測した欠落境界はCSI 0 cを作り、正当なDA1と区別できない")
    func recordedTransportGap() {
        let host = Host()
        let terminal = Terminal(delegate: host)
        // 実PTYの受信580チャンク目。ONLCR後の9,619,453..<9,638,909が欠落した。
        // SGR0の終端mを含む19,456バイトが失われた実測の末尾・先頭。
        let prefix = Array("\u{1b}[38;2;105;59;223mtruecolor-75113\u{1b}[0".utf8)
        let suffix = Array("ces \u{1b}[0m \u{1b}[38;2;0;0;0mtruecolor-75264\u{1b}[0m\r\n".utf8)
        terminal.feed(byteArray: prefix)
        #expect(host.responses.isEmpty)
        terminal.feed(byteArray: suffix)
        let expected = Array("\u{1b}[?65;4;1;2;6;21;22;17;28c".utf8)
        #expect(host.responses == expected)

        // 同じ受信バイトを、単独の正式な問い合わせとして送った結果と照合する。
        let queryHost = Host()
        let queryTerminal = Terminal(delegate: queryHost)
        queryTerminal.feed(text: "\u{1b}[0c")
        #expect(queryHost.responses == expected)
    }
}
