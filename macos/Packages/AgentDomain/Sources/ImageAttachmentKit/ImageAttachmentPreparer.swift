import AgentDomain
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PreparedImageAttachment: Sendable, Equatable {
    public let data: Data
    public let mediaType: String

    public init(data: Data, mediaType: String) {
        self.data = data
        self.mediaType = mediaType
    }
}

public enum ImageAttachmentPreparationError: Error, LocalizedError, Sendable {
    case tooLarge, tooMany, invalidImage, tooManyPixels, cannotFit

    public var errorDescription: String? {
        switch self {
        case .tooLarge: ImageAttachmentLimits.inputSizeMessage
        case .tooMany: ImageAttachmentLimits.countMessage
        case .invalidImage: "画像を読み込めませんでした"
        case .tooManyPixels: "画像は各辺8000ピクセルまでです。必要な部分を切り出してください"
        case .cannotFit: "解像度を保ったまま送信容量に収まりません。必要な部分を切り出してください"
        }
    }
}

/// ImageIOは専用ターゲットへ隔離し、AgentDomainのFoundationのみの依存を維持する。
public enum ImageAttachmentPreparer {
    public static let maxSendEdge = 8_000
    public static let maxInputPixels = maxSendEdge * maxSendEdge
    public static let maxInputEdge = maxSendEdge

    /// 画像を1枚ずつ処理し、巨大な画像の同時展開を避ける。
    public static func prepare(_ data: [Data]) async throws -> [PreparedImageAttachment] {
        let task = Task.detached(priority: .userInitiated) {
            guard data.count <= ImageAttachmentLimits.maxCount else {
                throw ImageAttachmentPreparationError.tooMany
            }
            return try data.map { bytes in
                try Task.checkCancellation()
                return try autoreleasepool { try prepareImage(bytes) }
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public static func prepareImage(_ data: Data) throws -> PreparedImageAttachment {
        let (source, width, height) = try checkedSource(data)
        let type = CGImageSourceGetType(source) as String?
        let originalMediaType: String? = switch type {
        case UTType.png.identifier: "image/png"
        case UTType.jpeg.identifier: "image/jpeg"
        default: nil
        }
        if let originalMediaType,
           data.count <= ImageAttachmentLimits.maxSendBytes,
           max(width, height) <= maxSendEdge {
            return PreparedImageAttachment(data: data, mediaType: originalMediaType)
        }
        // PNGとして収まるなら透明度の画素走査もJPEG用の展開も不要。
        if originalMediaType == "image/png" {
            let png = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
                throw ImageAttachmentPreparationError.invalidImage
            }
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
            guard CGImageDestinationFinalize(destination) else { throw ImageAttachmentPreparationError.invalidImage }
            if png.length <= ImageAttachmentLimits.maxSendBytes {
                return PreparedImageAttachment(data: png as Data, mediaType: "image/png")
            }
        }
        try Task.checkCancellation()
        let image = try thumbnail(source, edge: max(width, height))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        // 16bitのわずかな透明度を8bitの展開で丸め、不透明と誤判定することを避ける。
        let highPrecisionAlpha = properties?[kCGImagePropertyHasAlpha] as? Bool == true
            && (properties?[kCGImagePropertyDepth] as? Int ?? 8) > 8
        let hasAlpha = try highPrecisionAlpha || hasTransparency(image)
        // 文字・透明部分はPNGで保持する。同じ寸法で収まらなければ不透明画像だけJPEGも試す。
        if hasAlpha {
            if originalMediaType == "image/png" { throw ImageAttachmentPreparationError.cannotFit }
            let png = try encode(image, usePNG: true)
            if png.count <= ImageAttachmentLimits.maxSendBytes {
                return PreparedImageAttachment(data: png, mediaType: "image/png")
            }
            throw ImageAttachmentPreparationError.cannotFit
        }
        let jpeg = try encode(image, usePNG: false)
        if jpeg.count <= ImageAttachmentLimits.maxSendBytes {
            return PreparedImageAttachment(data: jpeg, mediaType: "image/jpeg")
        }
        throw ImageAttachmentPreparationError.cannotFit
    }

    /// プレビューの失敗はプレースホルダ表示にする。送信時はprepareでエラーを通知する。
    public static func preview(_ data: Data) -> Data? {
        do {
            let (source, _, _) = try checkedSource(data)
            return try encode(thumbnail(source, edge: 112), usePNG: true)
        } catch {
            return nil
        }
    }

    private static func checkedSource(_ data: Data) throws -> (CGImageSource, Int, Int) {
        guard data.count <= ImageAttachmentLimits.maxInputBytes else {
            throw ImageAttachmentPreparationError.tooLarge
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            throw ImageAttachmentPreparationError.invalidImage
        }
        guard width <= maxInputEdge, height <= maxInputEdge,
              width <= maxInputPixels / height else {
            throw ImageAttachmentPreparationError.tooManyPixels
        }
        return (source, width, height)
    }

    private static func thumbnail(_ source: CGImageSource, edge: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageAttachmentPreparationError.invalidImage
        }
        return image
    }

    private static func encode(_ image: CGImage, usePNG: Bool) throws -> Data {
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            bytes, (usePNG ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil
        ) else { throw ImageAttachmentPreparationError.invalidImage }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.95,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageAttachmentPreparationError.invalidImage
        }
        return bytes as Data
    }

    /// アルファチャンネルの有無ではなく実際の透明画素を調べる。不透明RGBAもJPEGを試せる。
    private static func hasTransparency(_ image: CGImage) throws -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        // 通常のRGBA8は既存の画素列を走査し、検査用の巨大な画像をもう1枚作らない。
        let alphaOffset: Int? = switch image.alphaInfo {
        case .first, .premultipliedFirst: 0
        case .last, .premultipliedLast: 3
        default: nil
        }
        if image.bitsPerComponent == 8, image.bitsPerPixel == 32, let alphaOffset,
           let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
           CFDataGetLength(data) >= image.bytesPerRow * image.height {
            let offset = image.bitmapInfo.contains(.byteOrder32Little) ? 3 - alphaOffset : alphaOffset
            for row in 0..<image.height {
                for column in 0..<image.width where bytes[row * image.bytesPerRow + column * 4 + offset] < 255 {
                    return true
                }
            }
            return false
        }
        // RGBA8に統一して16bit/インデックス画像でも同じ検査を行う。
        var alpha = Data(count: image.width * image.height * 4)
        return try alpha.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ImageAttachmentPreparationError.invalidImage
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] < 255 }
        }
    }
}
