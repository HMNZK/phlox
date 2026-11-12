#if os(macOS)
import AppKit
import SwiftUI
import Testing
import DesignSystem

@Suite("カードの活動表示の描画", .serialized)
@MainActor
struct CardActivityAppearanceTests {
    @Test("既定の点描は他の画面で使う無彩色を維持する")
    func defaultOrbRemainsMonochrome() throws {
        let image = try hostedPixels(
            ThinkingOrbView(state: .searching, size: .large, isVisible: false)
        )

        #expect(image.visibleInkCount > 10)
        #expect(image.chromaticHueBins.isEmpty)
    }

    @Test("カード向けの点描は複数の色相で描く")
    func cardOrbContainsMultipleHues() throws {
        let image = try hostedPixels(
            ThinkingOrbView(state: .searching, size: .large, isVisible: false, colorStyle: .rainbow)
        )

        #expect(image.visibleInkCount > 10)
        #expect(image.chromaticHueBins.count >= 3)
    }

    @Test("非表示の虹色点描は同じ静止フレームを再現する")
    func hiddenRainbowOrbReproducesTheSameFrame() throws {
        let first = try hostedPixels(
            ThinkingOrbView(state: .editing, size: .large, isVisible: false, colorStyle: .rainbow)
        )
        let second = try hostedPixels(
            ThinkingOrbView(state: .editing, size: .large, isVisible: false, colorStyle: .rainbow)
        )

        #expect(first.visibleInkCount > 10)
        #expect(first.chromaticHueBins.count >= 3)
        let identicalFrames = first.pixels == second.pixels
        #expect(identicalFrames)
    }

    @Test("非表示のコマンドは指定した等幅書体を斜体にせず静止表示する")
    func hiddenCommandPreservesItsMonospacedFont() throws {
        let font = Font.system(size: 15, weight: .medium, design: .monospaced)
        let command = try textPixels(
            ShimmerTextView(text: "git status", font: font, pointSize: 15, color: .white,
                            isVisible: false, style: .command)
        )
        let expected = try textPixels(Text("git status").font(font).foregroundStyle(.white))

        #expect(command.visibleInkCount > 10)
        let identicalCommandPixels = command.pixels == expected.pixels
        #expect(identicalCommandPixels)
    }

    @Test("ファイル名は指定書体を保ち、既存の短いラベルは斜体を保つ")
    func fileAndLegacyLabelsPreserveTheirTypography() throws {
        let font = Font.system(size: 16, weight: .semibold)
        let file = try textPixels(
            ShimmerTextView(text: "Package.swift", font: font, pointSize: 16, color: .white,
                            isVisible: false, style: .file)
        )
        let expectedFile = try textPixels(Text("Package.swift").font(font).foregroundStyle(.white))
        let legacy = try textPixels(
            ShimmerTextView(text: "Thinking...", font: font, pointSize: 16, color: .white,
                            isVisible: false)
        )
        let expectedLegacy = try textPixels(Text("Thinking...").font(font.italic()).foregroundStyle(.white))

        #expect(file.visibleInkCount > 10)
        #expect(legacy.visibleInkCount > 10)
        let identicalFilePixels = file.pixels == expectedFile.pixels
        #expect(identicalFilePixels)
        let identicalLegacyPixels = legacy.pixels == expectedLegacy.pixels
        #expect(identicalLegacyPixels)
    }
}

@MainActor
private func hostedPixels(_ content: some View) throws -> AppearanceImage {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: content
        .frame(width: 64, height: 64)
        .background(.black)
        .environment(\.colorScheme, .dark))
    host.frame = NSRect(x: 0, y: 0, width: 64, height: 64)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return AppearanceImage(bitmap)
}

@MainActor
private func textPixels(_ content: some View) throws -> AppearanceImage {
    let renderer = ImageRenderer(content: content
        .frame(width: 180, height: 32, alignment: .leading)
        .background(.black)
        .environment(\.colorScheme, .dark))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    return AppearanceImage(NSBitmapImageRep(cgImage: image))
}

private struct AppearanceImage {
    let pixels: [AppearancePixel]

    init(_ bitmap: NSBitmapImageRep) {
        pixels = (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).compactMap { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
                return AppearancePixel(color)
            }
        }
    }

    var visibleInkCount: Int { pixels.filter { $0.brightness > 20 }.count }

    var chromaticHueBins: Set<Int> {
        Set(pixels.compactMap { pixel in
            guard pixel.brightness - min(pixel.red, pixel.green, pixel.blue) > 20 else { return nil }
            let color = NSColor(srgbRed: CGFloat(pixel.red) / 255,
                                green: CGFloat(pixel.green) / 255,
                                blue: CGFloat(pixel.blue) / 255,
                                alpha: 1)
            return Int(color.hueComponent * 6)
        })
    }
}

private struct AppearancePixel: Equatable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int

    init(_ color: NSColor) {
        red = Int((color.redComponent * 255).rounded())
        green = Int((color.greenComponent * 255).rounded())
        blue = Int((color.blueComponent * 255).rounded())
        alpha = Int((color.alphaComponent * 255).rounded())
    }

    var brightness: Int { max(red, green, blue) }
}
#endif
