import Foundation
import Testing
@testable import SessionFeature

private let rowWindowTestTime = Date(timeIntervalSince1970: 1_700_000_000)

private func rowWindowCommand(_ id: String, output: String = "output") -> ChatItem {
    .commandExecution(id: id, command: "command \(id)", output: output, timestamp: rowWindowTestTime)
}

@Suite("CommandGroupRowWindow white-box")
struct CommandGroupRowWindowWhiteboxTests {
    @Test func フィルタ後の表示対象行に対して末尾から上限を適用する() {
        let items = [
            rowWindowCommand("c1", output: "first"),
            rowWindowCommand("c2", output: ""),
            rowWindowCommand("c3", output: "third"),
            rowWindowCommand("c4", output: "fourth"),
        ]

        let slice = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: 2
        )

        #expect(slice.rows.map(\.id) == ["c3", "c4"])
        #expect(slice.hiddenRowCount == 1)
    }

    @Test func ヘッダは空のグループで過去時刻と非描画を返す() {
        let header = CommandGroupHeader(items: [], lastTranscriptID: nil, isTurnRunning: false)

        #expect(header.timestamp == .distantPast)
        #expect(!header.shouldRender)
        #expect(!header.isRunning)
    }
}
