import Foundation
import XCTest
import PhloxCore
@testable import Features

/// 大量のコマンド出力を取得しても、View に渡る配列を窓で制限することを固定する。
/// 実際の SwiftUI レイアウト時間は XCTest では測れないため、ここではその前段となる
/// 描画入力の件数・バイト数を観測する。
@MainActor
final class SubAgentFreezeWhiteboxTests: XCTestCase {
    func testHeavyTranscriptIsBoundedBeforeItReachesTheView() async {
        let body = String(repeating: "x", count: 20_000)
        let messages = (0..<300).map { index in
            ChatMessage.command(id: "m\(index)", command: "echo \(index)", output: body)
        }
        let api = MockAPI()
        await api.setSubAgentMessagesOutcome(.success(messages))
        let session = Session(
            id: "s1", name: "Rose", agent: .claudeCode, status: .running,
            subtitle: "proj", updatedAt: Date(timeIntervalSince1970: 0)
        )
        let viewModel = SubAgentDetailViewModel(session: session, subAgentID: "sa1", api: api)

        let clock = ContinuousClock()
        let start = clock.now
        await viewModel.load()
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(messages.reduce(0) { $0 + $1.outputUTF8ByteCount }, 6_000_000)
        XCTAssertEqual(viewModel.chatMessages.count, 300)
        XCTAssertEqual(viewModel.visibleMessages.count, SubAgentDetailViewModel.visibleMessageLimit)
        XCTAssertEqual(viewModel.hiddenMessageCount, 250)
        XCTAssertLessThan(elapsed, .seconds(1), "窓の計算は取得後のメインスレッド処理を長時間占有しない")
    }
}

private extension ChatMessage {
    var outputUTF8ByteCount: Int {
        guard case let .command(_, _, output) = self else { return 0 }
        return output.utf8.count
    }
}
