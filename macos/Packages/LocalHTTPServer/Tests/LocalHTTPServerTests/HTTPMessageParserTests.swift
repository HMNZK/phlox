import Foundation
import Testing
@testable import LocalHTTPServer

@Suite struct HTTPMessageParserTests {
    private func requestData(
        method: String = "POST",
        target: String = "/hook",
        headers: [String] = [],
        body: String = ""
    ) -> Data {
        let bodyData = Data(body.utf8)
        var lines = ["\(method) \(target) HTTP/1.1"]
        lines.append(contentsOf: headers)
        lines.append("Content-Length: \(bodyData.count)")
        lines.append("")
        lines.append("")
        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(bodyData)
        return data
    }

    @Test func parseExtractsMethodTargetHeadersAndBody() throws {
        let data = requestData(
            method: "POST",
            target: "/send",
            headers: ["Authorization: Bearer abc"],
            body: #"{"to":"x"}"#
        )

        let request = try HTTPMessageParser.parse(data)

        #expect(request.method == "POST")
        #expect(request.target == "/send")
        #expect(request.path == "/send")
        #expect(request.hasQuery == false)
        #expect(request.headers["authorization"] == "Bearer abc")
        #expect(request.body == Data(#"{"to":"x"}"#.utf8))
    }

    @Test func parseSplitsQueryAndKeepsRawTarget() throws {
        let data = requestData(method: "GET", target: "/sessions/abc/wait?timeout=5&sentinel=%3E")

        let request = try HTTPMessageParser.parse(data)

        #expect(request.target == "/sessions/abc/wait?timeout=5&sentinel=%3E")
        #expect(request.path == "/sessions/abc/wait")
        #expect(request.hasQuery == true)
        #expect(request.query["timeout"] == "5")
        // percent decode される
        #expect(request.query["sentinel"] == ">")
    }

    @Test func parseThrowsIncompleteWhenBodyShorterThanContentLength() {
        var data = Data("POST /hook HTTP/1.1\r\nContent-Length: 10\r\n\r\n".utf8)
        data.append(Data("12345".utf8))

        #expect(throws: HTTPMessageParserError.incomplete) {
            _ = try HTTPMessageParser.parse(data)
        }
    }

    @Test func parseThrowsPayloadTooLargeWhenContentLengthExceedsLimit() {
        let data = Data("POST /hook HTTP/1.1\r\nContent-Length: \(HTTPMessageParser.maxBodyLength + 1)\r\n\r\n".utf8)

        #expect(throws: HTTPMessageParserError.payloadTooLarge) {
            _ = try HTTPMessageParser.parse(data)
        }
    }

    @Test func exceedsMaxBodyLengthWithoutHeaderEndTriggersOnTotalSize() {
        let oversized = Data(repeating: UInt8(ascii: "a"), count: HTTPMessageParser.maxBodyLength + 1)

        #expect(HTTPMessageParser.exceedsMaxBodyLength(oversized))
        #expect(!HTTPMessageParser.isComplete(oversized))
    }

    @Test func bodyAtLimitIsParsed() throws {
        let body = String(repeating: "x", count: HTTPMessageParser.maxBodyLength)
        let data = requestData(body: body)

        let request = try HTTPMessageParser.parse(data)

        #expect(request.body.count == HTTPMessageParser.maxBodyLength)
    }
}

@Suite struct HTTPResponseSerializerTests {
    @Test func serializeBuildsStatusLineHeadersAndBody() {
        let data = HTTPResponseSerializer.serialize(
            statusCode: 404,
            statusText: "Not Found",
            contentType: "text/plain; charset=utf-8",
            body: Data("not found".utf8)
        )

        let expected = "HTTP/1.1 404 Not Found\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: 9\r\n"
            + "Connection: close\r\n"
            + "\r\n"
            + "not found"
        #expect(data == Data(expected.utf8))
    }

    @Test func serializeEmptyBodySetsZeroContentLength() {
        let data = HTTPResponseSerializer.serialize(
            statusCode: 200,
            statusText: "OK",
            contentType: "application/json; charset=utf-8",
            body: Data()
        )

        let text = String(data: data, encoding: .utf8)
        #expect(text?.contains("Content-Length: 0\r\n") == true)
        #expect(text?.hasSuffix("\r\n\r\n") == true)
    }
}
