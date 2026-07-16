// task-8 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-8.md — 画像入力を stream-json の image content block として送信する。
// PM の実 CLI 疎通確認済み: base64 画像ブロックは受理されモデルが内容に回答した。

import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class ImageMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws { lock.withLock { sent.append(data) } }
    func interrupt() async {}
    func close() async { continuation?.finish() }

    func sentJSONObjects() -> [[String: Any]] {
        lock.withLock {
            sent.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }
}

private func makeImageClient(_ mock: ImageMockTransport) -> ClaudeChatClient {
    ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "11111111-1111-4111-8111-111111111111"],
        transportFactory: { _, _, _, _ in mock }
    )
}

@Test func imageContent_turnStartBuildsTextAndImageBlocks() async throws {
    let mock = ImageMockTransport()
    let client = makeImageClient(mock)
    await client.start()

    let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0x02])
    try await client.turnStart([
        .text("この画像は何ですか"),
        .image(data: pngData, mediaType: "image/png"),
    ])

    let payload = try #require(mock.sentJSONObjects().last)
    let message = try #require(payload["message"] as? [String: Any])
    let content = try #require(message["content"] as? [[String: Any]])
    try #require(content.count == 2)

    #expect(content[0]["type"] as? String == "text")
    #expect(content[0]["text"] as? String == "この画像は何ですか")

    #expect(content[1]["type"] as? String == "image")
    let source = try #require(content[1]["source"] as? [String: Any])
    #expect(source["type"] as? String == "base64")
    #expect(source["media_type"] as? String == "image/png")
    #expect(source["data"] as? String == pngData.base64EncodedString())
    await client.close()
}

@Test func imageContent_textOnlyWireFormatUnchanged() async throws {
    let mock = ImageMockTransport()
    let client = makeImageClient(mock)
    await client.start()

    try await client.turnStart([.text("hello")])

    let payload = try #require(mock.sentJSONObjects().last)
    let message = try #require(payload["message"] as? [String: Any])
    let content = try #require(message["content"] as? [[String: Any]])
    try #require(content.count == 1)
    #expect(content[0]["type"] as? String == "text")
    #expect(content[0]["text"] as? String == "hello")
    await client.close()
}
