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
    @Test func 実行中のliveRecapを最優先する() {
        let title = CommandGroupTitle.derive(
            items: [recapCommand("c1", command: "swift test")],
            isRunning: true,
            liveRecap: "swift test を実行中"
        )

        #expect(title == "swift test を実行中")
    }

    @Test func 完了後は最後のコマンドを完了形で表示する() {
        let title = CommandGroupTitle.derive(
            items: [
                recapCommand("c1", command: "cat README.md"),
                recapCommand("c2", command: "swift test")
            ],
            isRunning: false,
            liveRecap: nil
        )

        #expect(title == "swift test を実行")
    }

    @Test func コマンドが無いグループは件数を表示する() {
        let items = [recapCommand("c1", command: nil), recapCommand("c2", command: "")]

        #expect(CommandGroupTitle.derive(items: items, isRunning: false, liveRecap: nil) == "ツール実行 ×2")
    }

    @Test func 長いコマンドのラベル全体は60文字でクランプする() {
        let command = String(repeating: "a", count: 61)
        let title = CommandGroupTitle.derive(
            items: [recapCommand("c1", command: command)],
            isRunning: false,
            liveRecap: nil
        )

        #expect(title == String(repeating: "a", count: 60) + "…")
    }

    @Test func 非実行中はliveRecapを無視する() {
        let title = CommandGroupTitle.derive(
            items: [recapCommand("c1", command: "cat README.md")],
            isRunning: false,
            liveRecap: "別の recap"
        )

        #expect(title == "cat README.md を読み込み")
    }

    @Test func 同じitemsからの導出は決定論的である() {
        let items = [recapCommand("c1", command: "git status")]

        #expect(
            CommandGroupTitle.derive(items: items, isRunning: false, liveRecap: nil)
                == CommandGroupTitle.derive(items: items, isRunning: false, liveRecap: nil)
        )
    }

    @Test(arguments: [
        "cd macos && swift build \\\n+          --configuration release",
        "cat <<'EOF' > /tmp/a.txt\nhello\nEOF",
        "# 前処理\nnpm test"
    ])
    func 複数行コマンドは先頭から表示し改行を含めない(command: String) {
        let title = CommandGroupTitle.derive(
            items: [recapCommand("c1", command: command)],
            isRunning: false,
            liveRecap: nil
        )
        let normalizedCommand = command
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        #expect(title.hasPrefix(normalizedCommand))
        #expect(!title.contains("\n"))
    }

    @Test func 実行中セルのliveTitleはderive経由でフォールバックする() {
        let items = [recapCommand("c1", command: "swift test")]
        let cell = CommandGroupCell(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: true,
            recap: { _ in nil }
        )

        let header = CommandGroupHeader(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: true
        )
        #expect(header.title == "swift test を実行")
        #expect(cell.liveTitle?(recapHeaderTime) == header.title)
    }

    @Test func 実行中セルはliveTitle配線を実描画へ反映する() {
        let items = [recapCommand("c1", command: "swift test")]
        let live = CommandGroupCell(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: true,
            recap: { _ in "LIVE RECAP" }
        )
        let fallback = CommandGroupCell(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: true,
            recap: { _ in nil }
        )

        let livePixels = ImageRenderer(content: live).cgImage?.dataProvider?.data as Data?
        let fallbackPixels = ImageRenderer(content: fallback).cgImage?.dataProvider?.data as Data?
        #expect(livePixels != nil)
        #expect(fallbackPixels != nil)
        #expect(livePixels != fallbackPixels)
    }

    @Test func 実行中と完了後のグループヘッダを描画できる() {
        let items = [recapCommand("c1", command: "swift test")]
        let running = CommandGroupCell(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: true,
            recap: { _ in "swift test を実行中" }
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
