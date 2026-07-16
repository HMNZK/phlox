import Testing
import Foundation
import PhloxCore

// task-1 受け入れテスト（PM 著・凍結）。契約: tasks/task-1.md ／ 正本: Phlox docs/specs/qr-pairing-contract.md v1
// phlox://pair?v=1&host=&port=&token=&name= のパースと型付きエラーの優先順を検証する。

private let validToken = String(repeating: "0123456789abcdef", count: 4) // 64桁 hex 小文字

@Suite("PairingPayloadParser 受け入れ（契約 v1）")
struct PairingPayloadAcceptanceTests {

    // MARK: - 正常系

    @Test("フル URL（name あり・percent-encoded 日本語）をパースする")
    func parsesFullURL() throws {
        let url = "phlox://pair?v=1&host=100.64.12.34&port=8765&token=\(validToken)&name=My%E3%81%AEMac"
        let payload = try PairingPayloadParser.parse(url).get()
        #expect(payload == PairingPayload(host: "100.64.12.34", port: 8765, token: validToken, name: "MyのMac"))
    }

    @Test("name 欠落は nil になる（任意パラメータ）")
    func parsesWithoutName() throws {
        let url = "phlox://pair?v=1&host=100.64.12.34&port=8765&token=\(validToken)"
        let payload = try PairingPayloadParser.parse(url).get()
        #expect(payload.name == nil)
        #expect(payload.host == "100.64.12.34")
    }

    @Test("パラメータ順序に依存しない")
    func parsesShuffledParams() throws {
        let url = "phlox://pair?token=\(validToken)&name=Studio&port=1&v=1&host=100.100.1.2"
        let payload = try PairingPayloadParser.parse(url).get()
        #expect(payload == PairingPayload(host: "100.100.1.2", port: 1, token: validToken, name: "Studio"))
    }

    @Test("未知のクエリパラメータは無視する（前方互換）")
    func ignoresUnknownParams() throws {
        let url = "phlox://pair?v=1&host=100.64.12.34&port=65535&token=\(validToken)&future=xyz&mode=2"
        let payload = try PairingPayloadParser.parse(url).get()
        #expect(payload.port == 65535)
    }

    @Test("同名パラメータの重複は最初の値を採用する")
    func firstDuplicateWins() throws {
        let url = "phlox://pair?v=1&host=100.0.0.1&host=100.0.0.2&port=8765&token=\(validToken)"
        let payload = try PairingPayloadParser.parse(url).get()
        #expect(payload.host == "100.0.0.1")
    }

    // MARK: - 異常系（エラー種別と優先順）

    private func error(of string: String) -> PairingPayloadError? {
        if case .failure(let e) = PairingPayloadParser.parse(string) { return e }
        return nil
    }

    @Test("scheme が phlox でない・pair でない・URL でない → notPairingURL")
    func rejectsNonPairingURL() {
        #expect(error(of: "https://pair?v=1&host=h&port=1&token=\(validToken)") == .notPairingURL)
        #expect(error(of: "phlox://connect?v=1&host=h&port=1&token=\(validToken)") == .notPairingURL)
        #expect(error(of: "こんにちは") == .notPairingURL)
        #expect(error(of: "") == .notPairingURL)
    }

    @Test("v 欠落 → unsupportedVersion(nil)、v=2 → unsupportedVersion(\"2\")")
    func rejectsWrongVersion() {
        #expect(error(of: "phlox://pair?host=100.0.0.1&port=8765&token=\(validToken)") == .unsupportedVersion(nil))
        #expect(error(of: "phlox://pair?v=2&host=100.0.0.1&port=8765&token=\(validToken)") == .unsupportedVersion("2"))
    }

    @Test("host 欠落・空 → missingHost")
    func rejectsMissingHost() {
        #expect(error(of: "phlox://pair?v=1&port=8765&token=\(validToken)") == .missingHost)
        #expect(error(of: "phlox://pair?v=1&host=&port=8765&token=\(validToken)") == .missingHost)
    }

    @Test("port 欠落・非整数・範囲外 → invalidPort")
    func rejectsInvalidPort() {
        #expect(error(of: "phlox://pair?v=1&host=100.0.0.1&token=\(validToken)") == .invalidPort)
        #expect(error(of: "phlox://pair?v=1&host=100.0.0.1&port=abc&token=\(validToken)") == .invalidPort)
        #expect(error(of: "phlox://pair?v=1&host=100.0.0.1&port=0&token=\(validToken)") == .invalidPort)
        #expect(error(of: "phlox://pair?v=1&host=100.0.0.1&port=65536&token=\(validToken)") == .invalidPort)
    }

    @Test("token 欠落・63桁・大文字 hex・非 hex → invalidToken")
    func rejectsInvalidToken() {
        let base = "phlox://pair?v=1&host=100.0.0.1&port=8765"
        #expect(error(of: base) == .invalidToken)
        #expect(error(of: base + "&token=" + String(validToken.dropLast())) == .invalidToken)
        #expect(error(of: base + "&token=" + validToken.uppercased()) == .invalidToken)
        #expect(error(of: base + "&token=" + String(repeating: "g", count: 64)) == .invalidToken)
    }

    @Test("エラー優先順: version 違反と token 違反が同時なら unsupportedVersion が先")
    func errorPrecedence() {
        #expect(error(of: "phlox://pair?v=9&host=&port=abc&token=bad") == .unsupportedVersion("9"))
        #expect(error(of: "phlox://pair?v=1&port=abc&token=bad") == .missingHost)
        #expect(error(of: "phlox://pair?v=1&host=100.0.0.1&port=abc&token=bad") == .invalidPort)
    }
}
