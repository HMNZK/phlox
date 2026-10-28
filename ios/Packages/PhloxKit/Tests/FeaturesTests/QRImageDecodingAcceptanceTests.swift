import Testing
import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
@testable import Features

// task-2 受け入れテスト（PM 著・凍結）。契約: tasks/task-2.md
// 写真読み取り経路の中核 QRImageDecoder: CIFilter で生成した契約 v1 QR 画像から
// ペイロード文字列を復元できること（ラウンドトリップ）。Vision はホスト macOS でも動作する。

private let contractURL = "phlox://pair?v=1&host=100.64.12.34&port=8765&token="
    + String(repeating: "0123456789abcdef", count: 4)
    + "&name=My%E3%81%AEMac"

private func makeQRImage(of string: String, scale: CGFloat = 8) throws -> CGImage {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    let output = try #require(filter.outputImage)
    let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let context = CIContext()
    return try #require(context.createCGImage(scaled, from: scaled.extent))
}

@Suite("QRImageDecoder 受け入れ（写真読み取り経路のラウンドトリップ）")
struct QRImageDecodingAcceptanceTests {

    @Test("Vision の内部エラーだけ旧方式で再試行する")
    func retriesOnlyInternalErrors() {
        let internalError = NSError(domain: VNErrorDomain, code: VNErrorCode.internalError.rawValue)
        let otherError = NSError(domain: "test", code: 1)
        let otherVisionError = NSError(domain: VNErrorDomain, code: VNErrorCode.invalidArgument.rawValue)
        for (errors, expectedCalls, expectedResult) in [
            ([NSError](), 1, "QR" as String?),
            ([internalError], 2, "QR" as String?),
            ([otherError], 1, nil),
            ([otherVisionError], 1, nil),
            ([internalError, otherError], 2, nil)
        ] {
            let request = VNDetectBarcodesRequest()
            request.revision = VNDetectBarcodesRequestRevision2
            var revisions: [Int] = []
            let result = QRImageDecoder.decodeQRString(request: request) { request in
                revisions.append(request.revision)
                if revisions.count <= errors.count { throw errors[revisions.count - 1] }
                return "QR"
            }
            #expect(result == expectedResult)
            #expect(revisions.count == expectedCalls)
            #expect(revisions.first == VNDetectBarcodesRequestRevision2)
            if expectedCalls == 2 { #expect(revisions.last == VNDetectBarcodesRequestRevision1) }
        }
        let request = VNDetectBarcodesRequest()
        request.revision = VNDetectBarcodesRequestRevision1
        var calls = 0
        let result = QRImageDecoder.decodeQRString(request: request) { _ in
            calls += 1
            throw internalError
        }
        #expect(result == nil)
        #expect(calls == 1)
        calls = 0
        let emptyResult = QRImageDecoder.decodeQRString(request: VNDetectBarcodesRequest()) { _ in
            calls += 1
            return nil
        }
        #expect(emptyResult == nil)
        #expect(calls == 1)
    }

    @Test("契約 v1 URL の QR 画像からペイロード文字列を復元する")
    func decodesContractURLRoundTrip() throws {
        let image = try makeQRImage(of: contractURL)
        #expect(QRImageDecoder.decodeQRString(from: image) == contractURL)
    }

    @Test("QR を含まない画像は nil を返す（クラッシュしない）")
    func returnsNilForPlainImage() throws {
        let plain = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let context = CIContext()
        let cgImage = try #require(context.createCGImage(plain, from: plain.extent))
        #expect(QRImageDecoder.decodeQRString(from: cgImage) == nil)
    }
}
