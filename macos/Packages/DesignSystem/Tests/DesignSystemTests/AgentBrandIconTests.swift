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

@Suite @MainActor struct AgentBrandIconTests {
    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func brandKindsMapToBuiltinDescriptor(kind: AgentKind) {
        let descriptor = AgentRegistry.descriptor(for: kind)
        let icon = AgentBrandIcon(descriptor: descriptor, size: 24)
        #expect(icon.descriptor.ref.builtinKind == kind)
    }
}
