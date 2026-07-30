import Foundation
import SwiftUI
import Testing
@testable import SessionFeature

private let recapHeaderTime = Date(timeIntervalSince1970: 1_700_000_000)

private func recapCommand(_ id: String, command: String?, output: String = "output") -> ChatItem {
    .commandExecution(id: id, command: command, output: output, timestamp: recapHeaderTime)
}

@Suite("Acceptance: ツール実行グループの recap ヘッダ")
@MainActor
struct AcceptanceCommandGroupRecapHeaderTests {
    @Test func 最後のコマンドそのものを表示する() {
        let title = CommandGroupTitle.derive(
            items: [
                recapCommand("c1", command: "cat README.md"),
                recapCommand("c2", command: "swift test")
            ]
        )

        #expect(title == "swift test")
    }

    @Test func コマンドが無いグループは件数を表示する() {
        let items = [recapCommand("c1", command: nil), recapCommand("c2", command: "")]

        #expect(CommandGroupTitle.derive(items: items) == "ツール実行 ×2")
    }

    @Test func 長いコマンドのラベル全体は60文字でクランプする() {
        let command = String(repeating: "a", count: 61)
        let title = CommandGroupTitle.derive(items: [recapCommand("c1", command: command)])

        #expect(title == String(repeating: "a", count: 60) + "…")
    }

    @Test func 同じitemsからの導出は決定論的である() {
        let items = [recapCommand("c1", command: "git status")]

        #expect(
            CommandGroupTitle.derive(items: items)
                == CommandGroupTitle.derive(items: items)
        )
    }

    @Test(arguments: [
        "cd macos && swift build \\\n+          --configuration release",
        "cat <<'EOF' > /tmp/a.txt\nhello\nEOF",
        "# 前処理\nnpm test"
    ])
    func 複数行コマンドは先頭から表示し改行を含めない(command: String) {
        let title = CommandGroupTitle.derive(items: [recapCommand("c1", command: command)])
        let normalizedCommand = command
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        #expect(title.hasPrefix(normalizedCommand))
        #expect(!title.contains("\n"))
    }

    @Test func 実行中セルもitemsからタイトルを導出する() {
        let items = [recapCommand("c1", command: "swift test")]
        let cell = CommandGroupCell(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: true
        )

        let header = CommandGroupHeader(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: true
        )
        #expect(header.title == "swift test")
        #expect(ImageRenderer(content: cell).cgImage != nil)
    }

    @Test func 実行中と完了後のグループヘッダを描画できる() {
        let items = [recapCommand("c1", command: "swift test")]
        let running = CommandGroupCell(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: true
        )
        let completed = CommandGroupCell(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false
        )

        #expect(ImageRenderer(content: running).cgImage != nil)
        #expect(ImageRenderer(content: completed).cgImage != nil)
    }

    @Test func 長い出力は省略中でも全文をコピーでき展開後は全行を描画する() {
        let output = (1...21).map { "line \($0)" }.joined(separator: "\n")
        let collapsed = CommandGroupOutputDisplay(output: output, isExpanded: false)
        let expanded = CommandGroupOutputDisplay(output: output, isExpanded: true)

        #expect(collapsed.isTruncated)
        #expect(collapsed.hiddenLineCount == 1)
        #expect(collapsed.displayedOutput == (1...20).map { "line \($0)" }.joined(separator: "\n"))
        #expect(collapsed.copyText == output)
        #expect(!expanded.isTruncated)
        #expect(expanded.displayedOutput == output)
    }
}
