import Testing
import Foundation
import PhloxCore

private let validToken = String(repeating: "0123456789abcdef", count: 4)

@Suite("PairingPayloadParser 白箱")
struct PairingPayloadParserTests {

    private func error(of string: String) -> PairingPayloadError? {
        if case .failure(let e) = PairingPayloadParser.parse(string) { return e }
        return nil
    }

    @Test("境界 port 1 と 65535 を受理する")
    func acceptsBoundaryPorts() throws {
        for port in [1, 65535] {
            let url = "phlox://pair?v=1&host=100.0.0.1&port=\(port)&token=\(validToken)"
            let payload = try PairingPayloadParser.parse(url).get()
            #expect(payload.port == port)
        }
    }

    @Test("name が空文字のとき nil になる")
    func emptyNameBecomesNil() throws {
        let url = "phlox://pair?v=1&host=100.0.0.1&port=8765&token=\(validToken)&name="
        let payload = try PairingPayloadParser.parse(url).get()
        #expect(payload.name == nil)
    }

    @Test("重複 port は最初の値を採用する")
    func firstDuplicatePortWins() throws {
        let url = "phlox://pair?v=1&host=100.0.0.1&port=1111&port=2222&token=\(validToken)"
        let payload = try PairingPayloadParser.parse(url).get()
        #expect(payload.port == 1111)
    }

    @Test("負の port は invalidPort")
    func rejectsNegativePort() {
        let url = "phlox://pair?v=1&host=100.0.0.1&port=-1&token=\(validToken)"
        if case .failure(let error) = PairingPayloadParser.parse(url) {
            #expect(error == .invalidPort)
        } else {
            Issue.record("expected invalidPort")
        }
    }

    @Test("token が 65 桁のとき invalidToken")
    func rejectsOverlongToken() {
        let url = "phlox://pair?v=1&host=100.0.0.1&port=8765&token=\(validToken)a"
        if case .failure(let error) = PairingPayloadParser.parse(url) {
            #expect(error == .invalidToken)
        } else {
            Issue.record("expected invalidToken")
        }
    }

    @Test("token に末尾行終端子が付いた 65 文字は invalidToken")
    func rejectsTokenWithTrailingLineTerminator() {
        let base = "phlox://pair?v=1&host=100.0.0.1&port=8765"
        #expect(error(of: base + "&token=" + validToken + "%0A") == .invalidToken)
        #expect(error(of: base + "&token=" + validToken + "%0D") == .invalidToken)
    }
}
