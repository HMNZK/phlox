import Testing
import Foundation
import PhloxCore
@testable import Features

private let validToken = String(repeating: "ab", count: 32)
private let validURL =
    "phlox://pair?v=1&host=100.64.12.34&port=8765&token=\(validToken)&name=Mac"

@Suite("QRScanScreen 白箱")
struct QRScanScreenTests {

    @Test("notPairingURL は専用の日本語メッセージ")
    func notPairingURLMessage() {
        #expect(QRScanCopy.message(for: .notPairingURL) == "ペアリング用の QR コードではありません")
        #expect(QRScanLogic.parse("https://example.com/pair?v=1") == .failure("ペアリング用の QR コードではありません"))
    }

    @Test("unsupportedVersion は専用の日本語メッセージ")
    func unsupportedVersionMessage() {
        #expect(QRScanCopy.message(for: .unsupportedVersion("2")) == "未対応の QR バージョンです")
        #expect(
            QRScanLogic.parse("phlox://pair?v=2&host=1.2.3.4&port=1&token=\(validToken)")
                == .failure("未対応の QR バージョンです")
        )
    }

    @Test("missingHost は専用の日本語メッセージ")
    func missingHostMessage() {
        #expect(QRScanCopy.message(for: .missingHost) == "ホスト情報が見つかりません")
        #expect(
            QRScanLogic.parse("phlox://pair?v=1&port=8765&token=\(validToken)")
                == .failure("ホスト情報が見つかりません")
        )
    }

    @Test("invalidPort は専用の日本語メッセージ")
    func invalidPortMessage() {
        #expect(QRScanCopy.message(for: .invalidPort) == "ポート番号が不正です")
        #expect(
            QRScanLogic.parse("phlox://pair?v=1&host=1.2.3.4&port=0&token=\(validToken)")
                == .failure("ポート番号が不正です")
        )
    }

    @Test("invalidToken は専用の日本語メッセージ")
    func invalidTokenMessage() {
        #expect(QRScanCopy.message(for: .invalidToken) == "トークンが不正です")
        #expect(
            QRScanLogic.parse("phlox://pair?v=1&host=1.2.3.4&port=8765&token=short")
                == .failure("トークンが不正です")
        )
    }

    @Test("有効 URL は PairingPayload を返す")
    func parsesValidURL() {
        let result = QRScanLogic.parse(validURL)
        guard case .success(let payload) = result else {
            Issue.record("expected success")
            return
        }
        #expect(payload.host == "100.64.12.34")
        #expect(payload.port == 8765)
        #expect(payload.token == validToken)
        #expect(payload.name == "Mac")
    }

    @Test("successMessage は name あり/なしで文言が変わる")
    func successMessages() {
        #expect(QRScanCopy.successMessage(name: "Lab") == "接続しました（Lab）")
        #expect(QRScanCopy.successMessage(name: nil) == "接続しました")
        #expect(QRScanCopy.successMessage(name: "") == "接続しました")
    }

    @Test("PairingURLNormalizer は scheme/host を lowercase 化する")
    func normalizesURLSchemeAndHost() throws {
        let url = try #require(URL(string: "PHLOX://PAIR?v=1&host=100.64.12.34&port=8765&token=\(validToken)"))
        let normalized = PairingURLNormalizer.normalizedString(from: url)
        #expect(normalized.hasPrefix("phlox://pair?"))
        let payload = try PairingPayloadParser.parse(normalized).get()
        #expect(payload.host == "100.64.12.34")
    }

    @Test("onApplied は applying→success で1回だけ発火する")
    func firesOnAppliedOnceOnSuccess() {
        #expect(
            QRScanAppliedCallbackLogic.shouldFireOnApplied(
                previousPhase: .applying,
                currentPhase: .success(name: "Mac"),
                hasAlreadyFired: false
            )
        )
        #expect(
            !QRScanAppliedCallbackLogic.shouldFireOnApplied(
                previousPhase: .applying,
                currentPhase: .success(name: "Mac"),
                hasAlreadyFired: true
            )
        )
    }

    @Test("onApplied は unreachable やパースエラー相当の phase では発火しない")
    func doesNotFireOnAppliedForUnreachableOrIdle() {
        #expect(
            !QRScanAppliedCallbackLogic.shouldFireOnApplied(
                previousPhase: .applying,
                currentPhase: .unreachable(guidance: "offline"),
                hasAlreadyFired: false
            )
        )
        #expect(
            !QRScanAppliedCallbackLogic.shouldFireOnApplied(
                previousPhase: .idle,
                currentPhase: .idle,
                hasAlreadyFired: false
            )
        )
        #expect(
            !QRScanAppliedCallbackLogic.shouldFireOnApplied(
                previousPhase: .idle,
                currentPhase: .applying,
                hasAlreadyFired: false
            )
        )
    }

    @Test("onApplied は二重 success 遷移でも1回だけ発火する")
    func firesOnAppliedOnlyOnceForDoubleSuccess() {
        #expect(
            QRScanAppliedCallbackLogic.shouldFireOnApplied(
                previousPhase: .applying,
                currentPhase: .success(name: nil),
                hasAlreadyFired: false
            )
        )
        #expect(
            !QRScanAppliedCallbackLogic.shouldFireOnApplied(
                previousPhase: .success(name: nil),
                currentPhase: .success(name: "Again"),
                hasAlreadyFired: false
            )
        )
        #expect(
            !QRScanAppliedCallbackLogic.shouldFireOnApplied(
                previousPhase: .applying,
                currentPhase: .success(name: "Again"),
                hasAlreadyFired: true
            )
        )
    }
}
