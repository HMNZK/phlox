import Foundation
import Testing
@testable import MobileProxy

@Suite struct PairingPayloadTests {
    private let validToken = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    private let host = "100.64.12.34"
    private let port = 8080

    // ---- 正常系（契約 v1 URL をスナップショット固定） ----

    @Test func fullParametersProduceContractURL() {
        let result = PairingPayload.make(
            host: host,
            port: port,
            token: validToken,
            name: "My Mac"
        )
        #expect(
            result == .success(
                PairingPayload(
                    host: host,
                    port: port,
                    token: validToken,
                    name: "My Mac",
                    urlString:
                        "phlox://pair?v=1&host=100.64.12.34&port=8080&token=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef&name=My%20Mac"
                )
            )
        )
    }

    @Test func omittedNameOmitsNameQueryParameter() {
        let result = PairingPayload.make(host: host, port: port, token: validToken)
        #expect(
            result == .success(
                PairingPayload(
                    host: host,
                    port: port,
                    token: validToken,
                    name: nil,
                    urlString:
                        "phlox://pair?v=1&host=100.64.12.34&port=8080&token=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                )
            )
        )
        if case .success(let payload) = result {
            #expect(!payload.urlString.contains("&name="))
        }
    }

    @Test func portLowerBoundaryIsAccepted() {
        let result = PairingPayload.make(host: host, port: 1, token: validToken)
        #expect(result.isSuccess)
        if case .success(let payload) = result {
            #expect(payload.urlString == "phlox://pair?v=1&host=100.64.12.34&port=1&token=\(validToken)")
        }
    }

    @Test func portUpperBoundaryIsAccepted() {
        let result = PairingPayload.make(host: host, port: 65_535, token: validToken)
        #expect(result.isSuccess)
        if case .success(let payload) = result {
            #expect(payload.urlString == "phlox://pair?v=1&host=100.64.12.34&port=65535&token=\(validToken)")
        }
    }

    // ---- name の percent-encoding ----

    @Test func nameWithWhitespaceIsPercentEncoded() {
        let result = PairingPayload.make(host: host, port: port, token: validToken, name: "My Mac")
        if case .success(let payload) = result {
            #expect(payload.urlString.hasSuffix("&name=My%20Mac"))
        } else {
            Issue.record("expected success")
        }
    }

    @Test func nameWithJapaneseIsPercentEncoded() {
        let result = PairingPayload.make(host: host, port: port, token: validToken, name: "田中のMac")
        if case .success(let payload) = result {
            #expect(payload.urlString.hasSuffix("&name=%E7%94%B0%E4%B8%AD%E3%81%AEMac"))
        } else {
            Issue.record("expected success")
        }
    }

    @Test func nameWithAmpersandIsPercentEncoded() {
        let result = PairingPayload.make(host: host, port: port, token: validToken, name: "a&b")
        if case .success(let payload) = result {
            #expect(payload.urlString.hasSuffix("&name=a%26b"))
        } else {
            Issue.record("expected success")
        }
    }

    // ---- 異常系: host ----

    @Test func nonIPv4HostFails() {
        #expect(PairingPayload.make(host: "example.com", port: port, token: validToken) == .failure(.invalidHost))
        #expect(PairingPayload.make(host: "100.64.1", port: port, token: validToken) == .failure(.invalidHost))
        #expect(PairingPayload.make(host: "256.1.1.1", port: port, token: validToken) == .failure(.invalidHost))
        #expect(PairingPayload.make(host: "", port: port, token: validToken) == .failure(.invalidHost))
    }

    // ---- 異常系: port ----

    @Test func portZeroFails() {
        #expect(PairingPayload.make(host: host, port: 0, token: validToken) == .failure(.invalidPort))
    }

    @Test func portAboveMaxFails() {
        #expect(PairingPayload.make(host: host, port: 65_536, token: validToken) == .failure(.invalidPort))
        #expect(PairingPayload.make(host: host, port: -1, token: validToken) == .failure(.invalidPort))
    }

    // ---- 異常系: token ----

    @Test func tokenTooShortFails() {
        let shortToken = String(validToken.dropLast())
        #expect(shortToken.count == 63)
        #expect(PairingPayload.make(host: host, port: port, token: shortToken) == .failure(.invalidToken))
    }

    @Test func uppercaseHexTokenFails() {
        let upperToken = validToken.replacingOccurrences(of: "a", with: "A")
        #expect(upperToken != validToken)
        #expect(PairingPayload.make(host: host, port: port, token: upperToken) == .failure(.invalidToken))
    }

    @Test func nonHexTokenFails() {
        var badToken = validToken
        badToken.replaceSubrange(badToken.startIndex ... badToken.startIndex, with: "g")
        #expect(PairingPayload.make(host: host, port: port, token: badToken) == .failure(.invalidToken))
    }

    // ---- BindMode 導出ヘルパー ----

    @Test func tailscaleBindModeProducesPayload() {
        let result = PairingPayload.make(
            bindMode: .tailscale(host),
            port: port,
            token: validToken,
            name: "Desk"
        )
        #expect(result.isSuccess)
        if case .success(let payload) = result {
            #expect(payload.host == host)
            #expect(payload.urlString.contains("host=100.64.12.34"))
        }
    }

    @Test func loopbackOnlyBindModeCannotGeneratePayload() {
        #expect(
            PairingPayload.make(bindMode: .loopbackOnly, port: port, token: validToken)
                == .failure(.unsupportedBindMode)
        )
    }

    @Test func explicitHostBindModeCannotGeneratePayload() {
        #expect(
            PairingPayload.make(bindMode: .explicitHost("127.0.0.1"), port: port, token: validToken)
                == .failure(.unsupportedBindMode)
        )
    }

    // ---- エラーメッセージに token が漏れない ----

    @Test func errorCasesDoNotExposeTokenInDescription() {
        let badToken = "G" + String(validToken.dropFirst())
        let result = PairingPayload.make(host: host, port: port, token: badToken)
        guard case .failure(let error) = result else {
            Issue.record("expected failure")
            return
        }
        let description = String(describing: error)
        #expect(!description.contains(validToken))
        #expect(!description.contains(badToken))
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
