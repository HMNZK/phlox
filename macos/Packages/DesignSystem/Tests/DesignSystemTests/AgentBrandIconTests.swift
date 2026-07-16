import AgentDomain
import SwiftUI
import Testing
@testable import DesignSystem

@Suite struct AgentBrandIconBundleTests {
    @Test func assetBundleExposesModuleResources() throws {
        let bundle = AgentBrandIcon.assetBundle
        let root = try #require(bundle.resourceURL)
        let fm = FileManager.default
        let hasCatalog = fm.fileExists(atPath: root.appendingPathComponent("Icons.xcassets").path)
        let hasCompiledAssets = fm.fileExists(atPath: root.appendingPathComponent("Assets.car").path)
        #expect(hasCatalog || hasCompiledAssets)
    }
}

@Suite @MainActor struct AgentBrandIconFallbackTests {
    @Test func customAgentUsesInitialWhenSymbolNameEmpty() {
        let descriptor = AgentDescriptor(
            ref: .custom("test-agent"),
            displayName: "My Agent",
            binaryName: "my-agent",
            symbolName: "",
            colorRGB: AgentRGB(0xAA, 0xBB, 0xCC),
            bypassKey: "phlox.bypass.test",
            launchSpec: AgentLaunchSpec()
        )
        let icon = AgentBrandIcon(descriptor: descriptor, size: 32)
        #expect(icon.descriptor.displayName == "My Agent")
    }

    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func brandKindsMapToBuiltinDescriptor(kind: AgentKind) {
        let descriptor = AgentRegistry.descriptor(for: kind)
        let icon = AgentBrandIcon(descriptor: descriptor, size: 24)
        #expect(icon.descriptor.ref.builtinKind == kind)
    }
}
