import Testing
import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
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
