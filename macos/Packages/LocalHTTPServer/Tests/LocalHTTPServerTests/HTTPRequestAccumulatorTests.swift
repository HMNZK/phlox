import Foundation
import Testing
@testable import LocalHTTPServer

@Suite struct HTTPRequestAccumulatorTests {
    @Test func singleChunkRequestCompletesAndParses() throws {
        var accumulator = HTTPRequestAccumulator()
        let data = Data("POST /hook HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello".utf8)

        let progress = try accumulator.append(data)

        #expect(progress == .complete)
        let request = try accumulator.makeRequest()
        #expect(request.method == "POST")
        #expect(request.target == "/hook")
        #expect(request.body == Data("hello".utf8))
    }

    @Test func headerTerminatorSplitAcrossChunksIsDetected() throws {
        var accumulator = HTTPRequestAccumulator()

        // \r\n\r\n の途中でチャンクが切れても境界をまたいで検出できる
        #expect(try accumulator.append(Data("POST /hook HTTP/1.1\r\nContent-Length: 2\r\n".utf8)) == .needsMore)
        #expect(try accumulator.append(Data("\r".utf8)) == .needsMore)
        #expect(try accumulator.append(Data("\n".utf8)) == .needsMore)
        #expect(try accumulator.append(Data("ab".utf8)) == .complete)

        let request = try accumulator.makeRequest()
        #expect(request.body == Data("ab".utf8))
    }

    @Test func bodyArrivingInMultipleChunksCompletesAtContentLength() throws {
        var accumulator = HTTPRequestAccumulator()

        #expect(try accumulator.append(Data("POST /hook HTTP/1.1\r\nContent-Length: 6\r\n\r\nfoo".utf8)) == .needsMore)
        #expect(try accumulator.append(Data("bar".utf8)) == .complete)

        let request = try accumulator.makeRequest()
        #expect(request.body == Data("foobar".utf8))
    }

    @Test func declaredContentLengthOverLimitThrowsPayloadTooLarge() {
        var accumulator = HTTPRequestAccumulator()
        let data = Data("POST /hook HTTP/1.1\r\nContent-Length: \(HTTPMessageParser.maxBodyLength + 1)\r\n\r\n".utf8)

        #expect(throws: HTTPMessageParserError.payloadTooLarge) {
            _ = try accumulator.append(data)
        }
    }

    @Test func accumulatedBodyOverLimitThrowsPayloadTooLarge() throws {
        // 宣言 Content-Length は上限内でも、受信済みボディが上限を超えた時点で
        // 完了判定より先に超過判定が走る(旧ループと同じ順序)
        var accumulator = HTTPRequestAccumulator(maxBodyLength: 8)

        _ = try accumulator.append(Data("POST /hook HTTP/1.1\r\nContent-Length: 5\r\n\r\n".utf8))

        #expect(throws: HTTPMessageParserError.payloadTooLarge) {
            _ = try accumulator.append(Data("0123456789".utf8))
        }
    }

    @Test func oversizedHeadersWithoutTerminatorThrowPayloadTooLarge() throws {
        var accumulator = HTTPRequestAccumulator(maxBodyLength: 8)

        #expect(throws: HTTPMessageParserError.payloadTooLarge) {
            _ = try accumulator.append(Data("123456789".utf8))
        }
    }

    @Test func makeRequestBeforeCompletionThrowsIncomplete() throws {
        var accumulator = HTTPRequestAccumulator()

        _ = try accumulator.append(Data("POST /hook HTTP/1.1\r\nContent-Length: 10\r\n\r\nshort".utf8))

        #expect(throws: HTTPMessageParserError.incomplete) {
            _ = try accumulator.makeRequest()
        }
    }

    @Test func bytesBeyondContentLengthAreKeptInBody() throws {
        // 旧 parse は Content-Length を超えた残余バイトもボディに含めて返していた(特性化)
        var accumulator = HTTPRequestAccumulator()

        let progress = try accumulator.append(Data("POST /hook HTTP/1.1\r\nContent-Length: 2\r\n\r\nabEXTRA".utf8))

        #expect(progress == .complete)
        let request = try accumulator.makeRequest()
        #expect(request.body == Data("abEXTRA".utf8))
    }

    @Test func missingContentLengthCompletesAtHeaderEnd() throws {
        // Content-Length 無指定は 0 扱い(旧 isComplete と同じ)
        var accumulator = HTTPRequestAccumulator()

        let progress = try accumulator.append(Data("GET /sessions HTTP/1.1\r\nAuthorization: Bearer x\r\n\r\n".utf8))

        #expect(progress == .complete)
        let request = try accumulator.makeRequest()
        #expect(request.method == "GET")
        #expect(request.body.isEmpty)
    }
}
