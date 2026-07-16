import AgentDomain
import AppKit
import SwiftUI
import Testing
@testable import DesignSystem

// task-1 受け入れテスト（PM 著・実装役は編集禁止 / loopflow acceptance_tests）
//
// 注意: SwiftPM の swift test は xcassets を actool でコンパイルしないため、ブランド画像
// そのものの実描画ピクセルはここでは検証できない（スパイク実証済み。実描画はフェーズ4 の
// xcodebuild ビルドで PM が確認する）。ここでは (a) API 契約とフォールバック描画、
// (b) アセットカタログの同梱を検証する。

@MainActor
private func renderPNG(_ view: some View, size: CGFloat = 32) -> Data? {
    let renderer = ImageRenderer(content: view.frame(width: size, height: size))
    renderer.scale = 2
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff)
    else { return nil }
    return rep.representation(using: .png, properties: [:])
}

private func hasMultipleColors(_ png: Data) -> Bool {
    guard let rep = NSBitmapImageRep(data: png) else { return false }
    var seen = Set<String>()
    let strideX = max(1, rep.pixelsWide / 16)
    let strideY = max(1, rep.pixelsHigh / 16)
    for x in stride(from: 0, to: rep.pixelsWide, by: strideX) {
        for y in stride(from: 0, to: rep.pixelsHigh, by: strideY) {
            if let color = rep.colorAt(x: x, y: y) {
                seen.insert(color.description)
                if seen.count > 1 { return true }
            }
        }
    }
    return false
}

@Test @MainActor
func agentBrandIcon_rendersAllBrandKindsWithoutCrash() throws {
    // ブランド 3 種は swift test 下では空白描画になりうるが、nil やクラッシュにはならないこと。
    for kind in [AgentKind.claudeCode, AgentKind.codex, AgentKind.cursor] {
        let descriptor = AgentRegistry.descriptor(for: kind)
        _ = try #require(renderPNG(AgentBrandIcon(descriptor: descriptor, size: 32)))
    }
}

@Test
func agentBrandIcon_assetCatalogShipsThreeBrandSVGs() throws {
    // swift test では xcassets が生のままバンドルへコピーされ、xcodebuild では Assets.car に
    // コンパイルされる。どちらの形態でも 3 ブランドのアセットが同梱されていることを検証する。
    let bundle = AgentBrandIcon.assetBundle
    let root = try #require(bundle.resourceURL)
    let fm = FileManager.default
    if fm.fileExists(atPath: root.appendingPathComponent("Assets.car").path) {
        return // actool コンパイル済み（xcodebuild 経路）
    }
    let expected: [String: String] = [
        "agent-brand-claude": "claude-ai-symbol.svg",
        "agent-brand-codex": "chatgpt-logo.svg",
        "agent-brand-cursor": "cursor-ai-code-icon.svg",
    ]
    for (imageset, svg) in expected {
        let url = root.appendingPathComponent("Icons.xcassets/\(imageset).imageset/\(svg)")
        #expect(fm.fileExists(atPath: url.path), "missing asset: \(imageset)/\(svg)")
    }
}
