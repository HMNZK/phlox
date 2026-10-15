import CryptoKit
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

/// 人工データのみ。識別子・本文・時刻を固定し、実際の grouping / budget に通す。
enum SidebarTranscriptFixture {
    struct Record: Codable {
        let id: String
        let kind: String
        let characters: Int
        let lines: Int
        let sha256: String
    }

    static let timestamp = Date(timeIntervalSince1970: 0)

    static func padded(_ prefix: String, count: Int) -> String {
        precondition(prefix.count <= count)
        return prefix + String(repeating: "あ", count: count - prefix.count)
    }

    static func table(_ id: String) -> String {
        let header = "|項目|説明|状態|備考|\n|---|---|---|---|\n"
        let rows = (0..<20).map { "|\(id)-\($0)|説明|完了|備考|" }
        let extra = 2_000 - header.count - rows.joined(separator: "\n").count
        return header + rows.enumerated().map { index, row in
            index == 0 ? String(row.dropLast()) + String(repeating: "表", count: extra) + "|" : row
        }.joined(separator: "\n")
    }

    static func code(_ id: String, lines: Int, count: Int, diff: Bool) -> String {
        let fence = diff ? "diff" : "swift"
        let header = "```\(fence)\n"
        let footer = "\n```"
        let rows = (0..<lines).map { index in
            diff ? "+ // \(id) 行\(index)" : "// \(id) 行\(index)"
        }
        let extra = count - header.count - footer.count - rows.joined(separator: "\n").count
        return header + rows.enumerated().map { index, row in
            index == 0 ? row + String(repeating: "文", count: extra) : row
        }.joined(separator: "\n") + footer
    }

    static var entries: [(id: String, kind: String, text: String)] {
        var result: [(id: String, kind: String, text: String)] = []
        result.reserveCapacity(540)
        for group in 0..<20 {
            let id = String(format: "fixture-%02d", group)
            result.append(("\(id)-long", "user", padded("\(id) 長い日本語入力\n", count: 4_000)))
            result.append(("\(id)-table", "agent", table(id)))
            result.append(("\(id)-code", "agent", code(id, lines: 50, count: 3_500, diff: false)))
            result.append(("\(id)-diff", "agent", code(id, lines: 30, count: 2_500, diff: true)))
            for index in 0..<3 {
                result.append(("\(id)-command-\(index)", "command", padded("人工出力\(index)\n", count: 200)))
            }
            for index in 0..<5 {
                result.append(("\(id)-short-\(index)", "user", padded("\(id) 短い入力\(index)\n", count: 100)))
            }
            for index in 0..<15 {
                result.append(("\(id)-answer-\(index)", "agent", padded("\(id) 日本語回答\(index)\n", count: 200)))
            }
        }
        return result
    }

    static var items: [ChatItem] {
        entries.map { entry in
            switch entry.kind {
            case "user": .userMessage(id: entry.id, text: entry.text, timestamp: timestamp)
            case "command": .commandExecution(id: entry.id, command: "printf 'fixture only'", output: entry.text, timestamp: timestamp)
            default: .agentMessage(id: entry.id, text: entry.text, timestamp: timestamp)
            }
        }
    }

    static var changeCards: [ChatItem] {
        (0..<20).map { index in
            let id = String(format: "card-%02d", index)
            let diff = (0..<30).map { padded("+ \(id) 行\($0) ", count: 80) }.joined(separator: "\n")
            return .fileChange(id: id, changes: [FilePatchChange(path: "fixture/\(id).swift", diff: diff, kind: "edit")], timestamp: timestamp)
        }
    }

    static var manifest: [Record] {
        entries.map { record(id: $0.id, kind: $0.kind, text: $0.text) } + changeCards.flatMap { item in
            guard case .fileChange(let id, let changes, _) = item else { return [Record]() }
            return changes.map { record(id: id, kind: "change-card", text: $0.diff) }
        }
    }

    static func record(id: String, kind: String, text: String) -> Record {
        Record(id: id, kind: kind, characters: text.count,
               lines: text.components(separatedBy: "\n").count,
               sha256: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined())
    }

    static func allowed(expansions: Int) -> Int {
        var window = TranscriptWindow()
        for _ in 0..<expansions { window.expand() }
        return TranscriptRenderBudget.allowedBlockCount(
            blocks: ChatTranscriptGrouping.blocks(from: items), requestedLimit: window.limit,
            defaultLimit: TranscriptWindow.defaultLimit, minimumBlocks: TranscriptRenderBudget.minimumBlocks
        )
    }
}

@Suite("SidebarTranscriptFixture")
struct SidebarTranscriptFixtureTests {
    @Test func fixedContentAndRealBudget() {
        let entries = SidebarTranscriptFixture.entries
        let items = SidebarTranscriptFixture.items
        let blocks = ChatTranscriptGrouping.blocks(from: items)
        #expect(entries.count == 540)
        #expect(Set(entries.map(\.id)).count == 540)
        #expect(blocks.count == 500)
        #expect(entries.filter { $0.kind != "command" }.reduce(0) { $0 + $1.text.count } == 310_000)
        #expect(entries.filter { $0.kind == "command" }.allSatisfy { $0.text.count == 200 })
        let canonical = entries.map { "\($0.id)\t\($0.kind)\t\($0.text)\n" }.joined()
        #expect(SidebarTranscriptFixture.record(id: "fixture", kind: "all", text: canonical).sha256
                == "b0f42f5ad8ed79e03ec13bd05cc766a3fdb98ff1e7ea2f02527a4696f6d566b3")
        #expect([0, 1, 4, 8].map { SidebarTranscriptFixture.allowed(expansions: $0) } == [9, 21, 39, 63])
        var window = TranscriptWindow()
        window.reveal(index: 0, totalCount: blocks.count)
        #expect(TranscriptRenderBudget.allowedBlockCount(
            blocks: blocks, requestedLimit: window.limit, defaultLimit: 50, minimumBlocks: 550
        ) == 500)
        for item in SidebarTranscriptFixture.changeCards {
            guard case .fileChange(_, let changes, _) = item else { Issue.record("not a change card"); continue }
            let lines = changes[0].diff.components(separatedBy: "\n")
            #expect(lines.count == 30)
            #expect(lines.allSatisfy { $0.count == 80 })
        }
        for group in 0..<20 {
            let id = String(format: "fixture-%02d", group)
            #expect(SidebarTranscriptFixture.table(id).count == 2_000)
            #expect(SidebarTranscriptFixture.table(id).components(separatedBy: "\n").count == 22)
            #expect(SidebarTranscriptFixture.code(id, lines: 50, count: 3_500, diff: false).count == 3_500)
            #expect(SidebarTranscriptFixture.code(id, lines: 30, count: 2_500, diff: true).count == 2_500)
        }
    }
}
