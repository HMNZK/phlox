import Foundation
import SwiftUI
import XCTest
import PhloxCore
@testable import Features

/// `ImageRenderer` の描画クロージャを呼ばず、テキストのレイアウト確定だけを計測する。
/// iOS 実機の所要時間ではなく、macOS ホスト上の相対比較用プローブである。
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

        await viewModel.load()

        XCTAssertEqual(messages.reduce(0) { $0 + $1.outputUTF8ByteCount }, 6_000_000)
        XCTAssertEqual(viewModel.chatMessages.count, 300)
        XCTAssertEqual(viewModel.visibleMessages.count, SubAgentDetailViewModel.visibleMessageLimit)
        XCTAssertEqual(viewModel.hiddenMessageCount, 250)
    }

    func testMeasuresUnboundedTranscriptLayoutOnMacProxy() {
        let measurements = [
            (count: 300, bytesPerMessage: 20_000),
            (count: 50, bytesPerMessage: 20_000),
            (count: 1, bytesPerMessage: 6_000_000),
        ].map { measureLayout(count: $0.count, bytesPerMessage: $0.bytesPerMessage) }

        for measurement in measurements {
            print(
                "layout-probe count=\(measurement.count) bytesPerMessage=\(measurement.bytesPerMessage) " +
                "totalBytes=\(measurement.totalBytes) elapsedSeconds=\(measurement.elapsedSeconds) " +
                "size=\(measurement.size)"
            )
            XCTAssertGreaterThan(measurement.size.height, 0, "ImageRenderer がレイアウトを確定すること")
        }
    }

    func testMeasuresRenderedBudgetLayoutOnMacProxy() {
        let source = String(repeating: "x", count: 6_000_000)
        let rendered = SubAgentDetailViewModel.renderedBody(source)
        let renderedText = rendered.head + rendered.tail
        let measurement = measureLayout(count: 1, body: renderedText)

        print(
            "layout-probe budgeted count=1 sourceBytes=\(source.utf8.count) " +
            "renderedBytes=\(renderedText.utf8.count) omittedBytes=\(rendered.omittedBytes) " +
            "elapsedSeconds=\(measurement.elapsedSeconds) size=\(measurement.size)"
        )
        XCTAssertLessThanOrEqual(renderedText.utf8.count, SubAgentDetailViewModel.maxRenderedBytesPerMessage)
        XCTAssertEqual(rendered.omittedBytes, source.utf8.count - renderedText.utf8.count)
        XCTAssertGreaterThan(measurement.size.height, 0, "ImageRenderer がレイアウトを確定すること")
    }

    private func measureLayout(count: Int, bytesPerMessage: Int) -> LayoutMeasurement {
        measureLayout(count: count, body: String(repeating: "x", count: bytesPerMessage))
    }

    private func measureLayout(count: Int, body: String) -> LayoutMeasurement {
        let view = VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                Text(body)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 390)

        let renderer = ImageRenderer(content: view)
        var size = CGSize.zero
        let clock = ContinuousClock()
        let start = clock.now
        renderer.render { renderedSize, _ in
            size = renderedSize
        }
        let elapsed = start.duration(to: clock.now)
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        return LayoutMeasurement(
            count: count,
            bytesPerMessage: body.utf8.count,
            totalBytes: count * body.utf8.count,
            elapsedSeconds: elapsedSeconds,
            size: size
        )
    }
}

private struct LayoutMeasurement {
    let count: Int
    let bytesPerMessage: Int
    let totalBytes: Int
    let elapsedSeconds: Double
    let size: CGSize
}

private extension ChatMessage {
    var outputUTF8ByteCount: Int {
        guard case let .command(_, _, output) = self else { return 0 }
        return output.utf8.count
    }
}
