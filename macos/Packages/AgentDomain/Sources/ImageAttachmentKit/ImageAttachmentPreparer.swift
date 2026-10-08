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
        case .tooManyPixels: "画像の解像度が大きすぎます（最大4000万画素・各辺32768ピクセル）"
        case .cannotFit: "画質を保ったまま画像を送信サイズに調整できませんでした"
        }
    }
}

/// ImageIOは専用ターゲットへ隔離し、AgentDomainのFoundationのみの依存を維持する。
public enum ImageAttachmentPreparer {
    public static let maxInputPixels = 40_000_000
    public static let maxInputEdge = 32_768
    public static let maxSendEdge = 8_000

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
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let hasAlpha = properties?[kCGImagePropertyHasAlpha] as? Bool == true
        let usePNG = hasAlpha || originalMediaType == "image/png"
        var edge = min(max(width, height), maxSendEdge)
        while edge > 0 {
            try Task.checkCancellation()
            let image = try thumbnail(source, edge: edge)
            let bytes = try encode(image, usePNG: usePNG)
            if bytes.count <= ImageAttachmentLimits.maxSendBytes {
                return PreparedImageAttachment(data: bytes, mediaType: usePNG ? "image/png" : "image/jpeg")
            }
            if edge <= 256 { break }
            edge = max(256, Int(Double(edge) * 0.85))
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
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageAttachmentPreparationError.invalidImage
        }
        return bytes as Data
    }
}
