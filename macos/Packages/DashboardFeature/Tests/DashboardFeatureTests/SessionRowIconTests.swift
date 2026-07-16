import AppKit
import SwiftUI
import AgentDomain
import DesignSystem
import Testing
@testable import DashboardFeature

/// task-4 白箱: サイドバー行のブランドアイコン寸法・descriptor 解決・描画スモーク。
/// 行ビュー本体は private のため `SessionSidebarRowIconLayout` と `AgentBrandIcon` を検証する。
@Suite("SessionRowIcon whitebox")
struct SessionRowIconTests {

    @Test
    func brandIconSizeIsWithinRowHeightBudget() {
        let size = SessionSidebarRowIconLayout.brandIconSize
        #expect(size >= 14)
        #expect(size <= 16)
    }

    @Test
    func descriptorResolvesBuiltinFromAgentRef() {
        let descriptor = SessionSidebarRowIconLayout.descriptor(for: .builtin(.cursor))
        #expect(descriptor.ref == .builtin(.cursor))
        #expect(descriptor.displayName == AgentRegistry.descriptor(for: .cursor).displayName)
    }

    @Test
    func descriptorResolvesCustomFallbackFromAgentRef() {
        let ref = AgentRef.custom("my-cli")
        let descriptor = SessionSidebarRowIconLayout.descriptor(for: ref)
        #expect(descriptor.ref == ref)
        #expect(descriptor.symbolName == "terminal")
    }

    @Test @MainActor
    func brandIconRendersWithoutCrashForSidebarDescriptors() throws {
        let builtinRefs: [AgentRef] = [
            .builtin(.claudeCode),
            .builtin(.codex),
            .builtin(.cursor),
        ]
        for ref in builtinRefs {
            let descriptor = SessionSidebarRowIconLayout.descriptor(for: ref)
            let image = try renderImage(from: AgentBrandIcon(
                descriptor: descriptor,
                size: SessionSidebarRowIconLayout.brandIconSize
            ))
            #expect(try #require(image.tiffRepresentation).isEmpty == false)
        }

        let customDescriptor = SessionSidebarRowIconLayout.descriptor(for: .custom("custom-agent"))
        let customImage = try renderImage(from: AgentBrandIcon(
            descriptor: customDescriptor,
            size: SessionSidebarRowIconLayout.brandIconSize
        ))
        #expect(try #require(customImage.tiffRepresentation).isEmpty == false)
    }
}

@MainActor
private func renderImage<V: View>(from view: V) throws -> NSImage {
    let renderer = ImageRenderer(
        content: view
            .padding(16)
            .frame(width: 120, height: 80, alignment: .topLeading)
            .background(DSColor.background)
    )
    renderer.scale = 1
    return try #require(renderer.nsImage)
}
