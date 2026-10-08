import AgentDomain
import CoreGraphics
import Foundation
import ImageAttachmentKit
import ImageIO
import Testing
import UniformTypeIdentifiers

private func fixture(width: Int, height: Int, alpha: Bool = false, noisy: Bool = false, type: UTType = .png) throws -> Data {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    if noisy {
        var state: UInt64 = 42
        for i in pixels.indices {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            pixels[i] = UInt8(truncatingIfNeeded: state)
        }
    }
    for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = alpha ? 128 : 255 }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Test func preservesSmallPNGAndJPEG() throws {
    for type in [UTType.png, .jpeg] {
        let original = try fixture(width: 64, height: 32, type: type)
        let prepared = try ImageAttachmentPreparer.prepareImage(original)
        #expect(prepared.data == original)
        #expect(prepared.mediaType == (type == .png ? "image/png" : "image/jpeg"))
    }
}

@Test func acceptsTwentyMBAndRejectsOneByteMore() throws {
    var original = try fixture(width: 64, height: 32)
    original.append(Data(count: ImageAttachmentLimits.maxInputBytes - original.count))
    #expect(try ImageAttachmentPreparer.prepareImage(original).data.count <= ImageAttachmentLimits.maxSendBytes)
    original.append(0)
    #expect(throws: ImageAttachmentPreparationError.self) { try ImageAttachmentPreparer.prepareImage(original) }
}

@Test func rejectsBrokenImage() {
    #expect(throws: ImageAttachmentPreparationError.self) {
        try ImageAttachmentPreparer.prepareImage(Data([0x89, 0x50, 0x4E, 0x47]))
    }
}

@Test func refusesToShrinkLargeTransparentPNG() throws {
    let original = try fixture(width: 1600, height: 1000, alpha: true, noisy: true)
    #expect(original.count > 4_194_304)
    #expect(throws: ImageAttachmentPreparationError.cannotFit) {
        try ImageAttachmentPreparer.prepareImage(original)
    }
}

@Test func convertsOpaquePNGWithoutReducingDimensions() throws {
    let original = try fixture(width: 1600, height: 1000, noisy: true)
    #expect(original.count > ImageAttachmentLimits.maxSendBytes)
    let prepared = try ImageAttachmentPreparer.prepareImage(original)
    #expect(prepared.data.count <= ImageAttachmentLimits.maxSendBytes)
    #expect(prepared.mediaType == "image/jpeg")
    let source = try #require(CGImageSourceCreateWithData(prepared.data as CFData, nil))
    let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 1600)
    #expect(props[kCGImagePropertyPixelHeight] as? Int == 1000)
}

@Test func acceptsFortyEightMegapixelsWithinProviderDimensions() throws {
    // 実際の48MP PNGを使う。毎回巨大な画素配列を生成して他の時間検査へ負荷をかけない。
    let path = try #require(Bundle.module.url(forResource: "48mp", withExtension: "png", subdirectory: "Fixtures"))
    let original = try Data(contentsOf: path)
    let source = try #require(CGImageSourceCreateWithData(original as CFData, nil))
    let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 8000)
    #expect(props[kCGImagePropertyPixelHeight] as? Int == 6000)
    let prepared = try ImageAttachmentPreparer.prepareImage(original)
    #expect(prepared.data == original)
}

@Test func rejectsTooManyPixelsBeforeDecoding() throws {
    let original = try fixture(width: 8001, height: 5000)
    #expect(throws: ImageAttachmentPreparationError.self) { try ImageAttachmentPreparer.prepareImage(original) }
}

@Test func preparesFourImagesInOrderAndRejectsFifth() async throws {
    let png = try fixture(width: 10, height: 20)
    let jpeg = try fixture(width: 30, height: 40, type: .jpeg)
    let prepared = try await ImageAttachmentPreparer.prepare([png, jpeg, png, jpeg])
    #expect(prepared.map(\.data) == [png, jpeg, png, jpeg])
    #expect(prepared.reduce(0) { $0 + $1.data.count } <= ImageAttachmentLimits.maxTotalSendBytes)
    await #expect(throws: ImageAttachmentPreparationError.self) {
        try await ImageAttachmentPreparer.prepare([png, png, png, png, png])
    }
}

@Test func convertsHEICToJPEG() throws {
    let original = try fixture(width: 64, height: 32, type: .heic)
    let prepared = try ImageAttachmentPreparer.prepareImage(original)
    #expect(prepared.mediaType == "image/jpeg")
    #expect(prepared.data.starts(with: [0xff, 0xd8]))
}
