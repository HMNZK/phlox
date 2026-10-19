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
        #expect(QRScanCopy.message(for: .notPairingURL) == "ペアリング用の QR ではありません")
        #expect(QRScanLogic.parse("https://example.com/pair?v=1") == .failure("ペアリング用の QR ではありません"))
    }

    @Test("unsupportedVersion は専用の日本語メッセージ")
    func unsupportedVersionMessage() {
        #expect(QRScanCopy.message(for: .unsupportedVersion("2")) == "この QR の版には対応していません")
        #expect(
            QRScanLogic.parse("phlox://pair?v=2&host=1.2.3.4&port=1&token=\(validToken)")
                == .failure("この QR の版には対応していません")
        )
    }

    @Test("missingHost は専用の日本語メッセージ")
    func missingHostMessage() {
        #expect(QRScanCopy.message(for: .missingHost) == "QR に接続先がありません")
        #expect(
            QRScanLogic.parse("phlox://pair?v=1&port=8765&token=\(validToken)")
                == .failure("QR に接続先がありません")
        )
    }

    @Test("invalidPort は専用の日本語メッセージ")
    func invalidPortMessage() {
        #expect(QRScanCopy.message(for: .invalidPort) == "ポート番号が正しくありません")
        #expect(
            QRScanLogic.parse("phlox://pair?v=1&host=1.2.3.4&port=0&token=\(validToken)")
                == .failure("ポート番号が正しくありません")
        )
    }

    @Test("invalidToken は専用の日本語メッセージ")
    func invalidTokenMessage() {
        #expect(QRScanCopy.message(for: .invalidToken) == "QR のトークンが正しくありません")
        #expect(
            QRScanLogic.parse("phlox://pair?v=1&host=1.2.3.4&port=8765&token=short")
                == .failure("QR のトークンが正しくありません")
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

    @Test("成功の見出しは name を含み、再接続の案内は接続先を保つ")
    func successMessages() {
        #expect(QRScanCopy.successTitle(name: "Lab") == "接続しました（Lab）")
        #expect(QRScanCopy.successTitle(name: nil) == "接続しました")
        #expect(QRScanCopy.successTitle(name: "") == "接続しました")
        #expect(QRScanCopy.reconnectTitle == "QR で再接続")
        #expect(QRScanCopy.reconnectGuidance == "読み取れるまで、今の接続先は変わりません。")
    }

    @Test("P1 から P5 はカタログの文言・順序・技術値を使う")
    func pairingErrorsHaveCatalogCopy() {
        let scannedInputs = [
            "https://company.example/login",
            "phlox://pair?v=2",
            "phlox://pair?v=1&port=8765&token=\(validToken)",
            "phlox://pair?v=1&host=mac&port=99999&token=\(validToken)",
            "phlox://pair?v=1&host=mac&port=8765&token=invalid",
        ]
        let cases: [(PairingPayloadError, String, String, String, String)] = [
            (
                .notPairingURL,
                "ペアリング用の QR ではありません",
                "読み取った QR は Phlox の接続用ではありません。",
                "Mac の Phlox が表示したペアリング用の QR を読み取ってください。",
                "https://company.example"
            ),
            (
                .unsupportedVersion("2"),
                "この QR の版には対応していません",
                "QR の版（v）が無いか、このアプリが読めない版です。",
                "iPhone と Mac の Phlox を両方とも最新にしてから、QR を表示し直してください。",
                "phlox://pair?v=2"
            ),
            (
                .missingHost,
                "QR に接続先がありません",
                "QR の中に Mac のアドレス（host）が入っていません。",
                "Mac で QR を表示し直して、もう一度読み取ってください。",
                "phlox://pair?v=1&port=8765&token=…"
            ),
            (
                .invalidPort,
                "ポート番号が正しくありません",
                "QR の中のポート番号が、使える範囲（1〜65535）にありません。",
                "Mac の Phlox の設定でポートを確かめ、QR を表示し直してください。",
                "phlox://pair?v=1&host=mac&port=99999&token=…"
            ),
            (
                .invalidToken,
                "QR のトークンが正しくありません",
                "QR の中の接続の鍵（トークン）の形が違います。",
                "Mac で QR を表示し直して、もう一度読み取ってください。",
                "token=…（64 桁の小文字 16 進ではない）"
            ),
        ]
        for (index, entry) in cases.enumerated() {
            let (error, title, cause, nextStep, detail) = entry
            let presentation = QRScanCopy.presentation(for: error, scannedString: scannedInputs[index])
            #expect(presentation.title == title)
            #expect(presentation.cause == cause)
            #expect(presentation.nextStep == nextStep)
            #expect(presentation.technicalDetail == detail)
            #expect(presentation.recoveryAction == "もう一度スキャン")
            #expect(presentation.isNeutral == false)
        }
    }

    @Test("QRエラーは実入力の接続値を使い、資格情報と未知の項目を表示しない")
    func pairingDetailsUseScannedInputWithoutSecrets() {
        let missingHost = "phlox://pair?v=1&port=9123&token=\(validToken)&name=secret-name&password=secret#secret-fragment"
        #expect(QRScanCopy.presentation(for: .missingHost, scannedString: missingHost).technicalDetail
            == "phlox://pair?v=1&port=9123&token=…")
        let invalidPort = "phlox://pair?v=1&host=mac.example&port=70000&token=\(validToken)"
        #expect(QRScanCopy.presentation(for: .invalidPort, scannedString: invalidPort).technicalDetail
            == "phlox://pair?v=1&host=mac.example&port=70000&token=…")
        let notPairing = "https://user:password@company.example/private-secret?token=secret&key=secret#secret"
        #expect(QRScanCopy.presentation(for: .notPairingURL, scannedString: notPairing).technicalDetail
            == "https://company.example")
        let version = "phlox://pair?v=3&v=4&host=mac&port=9123&token=\(validToken)"
        #expect(QRScanCopy.presentation(for: .unsupportedVersion("3"), scannedString: version).technicalDetail
            == "phlox://pair?v=3&host=mac&port=9123&token=…")
        let malicious = "phlox://pair?v=secret%26token%3Dprivate&host=secret%40private&port=secret&token=\(validToken)"
        #expect(QRScanCopy.presentation(for: .unsupportedVersion("secret&token=private"), scannedString: malicious).technicalDetail
            == "phlox://pair?v=…&host=…&port=…&token=…")
        #expect(QRScanCopy.presentation(for: .notPairingURL, scannedString: "secret").technicalDetail == nil)
        #expect(QRScanCopy.presentation(for: .invalidToken, scannedString: validURL).technicalDetail
            == "token=…（64 桁の小文字 16 進ではない）")
    }

    @Test("P6 と K1 はカタログどおりの文言・操作を持つ")
    func imageQRAndCameraFailuresHaveCatalogCopy() {
        let p6 = QRScanCopy.imageQRNotFoundPresentation
        #expect(p6.title == "画像から QR を見つけられません")
        #expect(p6.cause == "選んだ画像の中に、読み取れる QR がありませんでした。")
        #expect(p6.nextStep == "QR 全体がはっきり写ったスクリーンショットを選んでください。")
        #expect(p6.technicalDetail == nil)
        #expect(p6.recoveryAction == "写真から読み取る")

        let k1 = QRScanCopy.cameraUnavailablePresentation
        #expect(k1.title == "カメラを使えません")
        #expect(k1.cause == "カメラへのアクセスが許可されていません。")
        #expect(k1.nextStep == "Mac の QR をスクリーンショットにして、写真から読み取れます。")
        #expect(k1.technicalDetail == nil)
        #expect(k1.recoveryAction == "写真から読み取る")
        #expect(k1.isNeutral)
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
