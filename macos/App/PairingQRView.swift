import CoreImage
import CoreImage.CIFilterBuiltins
import DesignSystem
import SwiftUI

/// QR ペアリング用のペイロードを CoreImage で符号化して表示するビュー。
/// ImageRenderer によるオフスクリーン描画確認のため、状態は外部から注入する。
public struct PairingQRView: View {
  public let payloadString: String
  public let warningText: String
  public let imageSize: CGFloat

  public init(
    payloadString: String =
      "phlox://pair?v=1&host=100.64.12.34&port=8765&token=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    warningText: String = "QR にはフルアクセス権限のトークンが含まれます。60 秒後に自動的に非表示になります。",
    imageSize: CGFloat = 200
  ) {
    self.payloadString = payloadString
    self.warningText = warningText
    self.imageSize = imageSize
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: DSSpacing.s) {
      if let qrImage = Self.makeQRImage(from: payloadString, targetSize: imageSize) {
        Image(nsImage: qrImage)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
          .frame(width: imageSize, height: imageSize)
          .accessibilityLabel("ペアリング用 QR コード")
      }
      Text(warningText)
        .font(DSFont.caption)
        .foregroundStyle(DSColor.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// `CIFilter.qrCodeGenerator` で QR 画像を生成する。
  static func makeQRImage(from string: String, targetSize: CGFloat) -> NSImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let outputImage = filter.outputImage else { return nil }

    let extent = outputImage.extent
    guard extent.width > 0, extent.height > 0 else { return nil }

    let scale = targetSize / extent.width
    let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let context = CIContext()
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

    return NSImage(
      cgImage: cgImage,
      size: NSSize(width: scaled.extent.width, height: scaled.extent.height)
    )
  }
}
