import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Contract: Codex 画像入力 seam")
struct ContractCodexImageInputSeamTests {
    @Test("inputModalities の image と legacy image_url を区別する")
    func nativeCapabilityIsDistinctFromLegacyWire() throws {
        let model = try JSONDecoder().decode(
            AppServerModel.self,
            from: Data(#"{"id":"m","displayName":"m","description":"","supportedReasoningEfforts":[],"defaultReasoningEffort":"medium","isDefault":false,"inputModalities":["text","image"]}"#.utf8)
        )
        let image = try JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(UserInput.imageURL("https://example.invalid/a.png"))
        )

        #expect(model.inputModalities == ["text", "image"])
        #expect(image["type"] == JSONValue.string("image"))
        #expect(image["image_url"] == nil)
    }

    @Test("native localImage の path/detail は lossless")
    func localImageWireIsLossless() throws {
        let input = UserInput.localImage(path: "/tmp/image.png", detail: "high")
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(input))
        let decoded = try JSONDecoder().decode(UserInput.self, from: JSONEncoder().encode(raw))

        #expect(decoded == input)
        #expect(raw == JSONValue.object([
            "type": JSONValue.string("localImage"),
            "path": JSONValue.string("/tmp/image.png"),
            "detail": JSONValue.string("high"),
        ]))
    }

    @Test("画像付き input は text-only payload に縮退しない")
    func imageInputCannotDegradeToTextOnly() throws {
        let inputs: [UserInput] = [.text("本文"), .localImage(path: "/tmp/image.png", detail: nil)]
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(inputs))
        guard case .array(let values) = raw else {
            Issue.record("画像付き input が配列でない")
            return
        }
        #expect(values.count == 2)
        #expect(values.contains { $0["type"] == JSONValue.string("localImage") })
    }

    @Test("実 CodexAppServerClient は native localImage を turn/start へ渡す")
    func clientForwardsNativeLocalImage() async throws {
        let transport = ImageInputTransport()
        let client = CodexAppServerClient(transport: transport)
        do {
            await client.start()

            _ = try await client.turnStart(TurnStartParams(
                threadId: "thread-image",
                input: [
                    .text("本文"),
                    .localImage(path: "/tmp/image.png", detail: "high"),
                ]
            ))

            let request = try #require(await transport.firstRequest(method: "turn/start"))
            #expect(request["params"]?["input"] == JSONValue.array([
                .object(["type": .string("text"), "text": .string("本文")]),
                .object([
                    "type": .string("localImage"),
                    "path": .string("/tmp/image.png"),
                    "detail": .string("high"),
                ]),
            ]))
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

}

private final class ImageInputTransport: AppServerTransport, @unchecked Sendable {
    private actor Recorder {
        private var messages: [JSONValue] = []

        func append(_ message: JSONValue) {
            messages.append(message)
        }

        func first(method: String) -> JSONValue? {
            messages.first { $0["method"]?.stringValue == method }
        }
    }

    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let recorder = Recorder()

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func send(_ data: Data) async throws {
        let line = data.firstIndex(of: 0x0A).map { Data(data[..<$0]) } ?? data
        let request = try JSONDecoder().decode(JSONValue.self, from: line)
        await recorder.append(request)
        guard let id = request["id"]?.intValue else { return }
        let response = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "result": .object([:]),
        ])
        continuation.yield(try JSONEncoder().encode(response))
    }

    func close() async {
        continuation.finish()
    }

    func firstRequest(method: String) async -> JSONValue? {
        await recorder.first(method: method)
    }
}
