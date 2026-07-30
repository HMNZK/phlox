import SwiftUI
import Testing
@testable import SessionFeature

@Suite("Chat code card acceptance (task-6)")
@MainActor
struct AcceptanceChatCodeCardTests {
    @Test(arguments: [
        ("Read Sources/App.swift", "Read", "Sources/App.swift"),
        ("WebSearch SwiftUI", "WebSearch", "SwiftUI"),
        ("Reader Sources/App.swift", "Bash", "Reader Sources/App.swift"),
        ("", "Bash", ""),
    ])
    func ツール名は先頭トークン完全一致だけを分離する(command: String, label: String, body: String) {
        let result = CommandToolLabel.derive(command: command)
        #expect(result.label == label)
        #expect(result.body == body)
    }

    @Test
    func shellハイライトは対象トークンを分類し壊れた引用符でも落ちない() {
        let tokens = ChatCodeHighlighter.tokenizeShell("git commit -m \"message\" | tee $LOG 2> err # note")
        #expect(tokens.contains { $0.kind == .command && $0.text == "git" })
        #expect(tokens.contains { $0.kind == .subcommand && $0.text == "commit" })
        #expect(tokens.contains { $0.kind == .option && $0.text == "-m" })
        #expect(tokens.contains { $0.kind == .string && $0.text == "\"message\"" })
        #expect(tokens.contains { $0.kind == .operator && $0.text == "|" })
        #expect(tokens.contains { $0.kind == .variable && $0.text == "$LOG" })
        #expect(tokens.contains { $0.kind == .comment && $0.text == "# note" })
        #expect(!ChatCodeHighlighter.tokenizeShell("echo value#suffix").contains { $0.kind == .comment })
        #expect(String(ChatCodeHighlighter.computeShellHighlight("echo \"broken" ).characters) == "echo \"broken")
    }

    @Test
    func 改行後の先頭語をコマンドとして分類する() {
        let tokens = ChatCodeHighlighter.tokenizeShell("echo first\ngrep second")
        #expect(tokens.contains { $0.kind == .command && $0.text == "grep" })
    }

    @Test
    func Swiftハイライトの既存トークン分類は不変である() {
        #expect(ChatCodeHighlighter.tokens(for: "func make() { let value = 1 }", path: "A.swift") == [
            .init(text: "func", kind: .keyword), .init(text: " make() { ", kind: .plain),
            .init(text: "let", kind: .keyword), .init(text: " value = ", kind: .plain),
            .init(text: "1", kind: .number), .init(text: " }", kind: .plain),
        ])
    }

    @Test
    func コードカードをImageRendererで描画できる() {
        let card = ChatCodeCard(copyText: "echo hi", copyAccessibilityIdentifier: "test.copy") {
            Text("Bash")
        } content: {
            Text("$ echo hi")
        }
        #expect(ImageRenderer(content: card.frame(width: 360)).nsImage != nil)
    }

    @Test
    func 複数行コマンドの継続行はImageRenderer上でプロンプト直後から始まる() throws {
        let display = CommandGroupExecutionDisplayData(command: "npm test\nnpm run lint", output: "")
        let command = HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("$ ")
            Text(display.highlightedCommand)
        }
        .font(.system(size: 13, design: .monospaced))
        .foregroundStyle(.black)
        .fixedSize()

        let renderer = ImageRenderer(content: command)
        guard let image = renderer.cgImage else {
            Issue.record("ImageRenderer が CGImage を生成しなかった")
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        let rows = (0..<bitmap.pixelsHigh).filter { y in
            (0..<bitmap.pixelsWide).contains { x in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1
            }
        }
        let lineRanges = contiguousRanges(rows)
        #expect(lineRanges.count == 2)
        guard lineRanges.count == 2 else { return }

        let continuationStart = leftmostInkX(in: bitmap, rows: lineRanges[1])
        #expect(continuationStart == 18)
    }

    private func contiguousRanges(_ rows: [Int]) -> [Range<Int>] {
        guard let first = rows.first else { return [] }
        var ranges: [Range<Int>] = []
        var start = first
        var previous = first
        for row in rows.dropFirst() {
            if row > previous + 1 {
                ranges.append(start..<(previous + 1))
                start = row
            }
            previous = row
        }
        ranges.append(start..<(previous + 1))
        return ranges
    }

    private func leftmostInkX(in bitmap: NSBitmapImageRep, rows: Range<Int>) -> Int {
        (0..<bitmap.pixelsWide).first { x in
            rows.contains { y in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1
            }
        } ?? -1
    }
}
