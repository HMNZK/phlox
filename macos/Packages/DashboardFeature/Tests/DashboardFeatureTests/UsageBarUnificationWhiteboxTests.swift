import AgentDomain
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("Usage バー統一 whitebox（task-4）") @MainActor
struct UsageBarUnificationWhiteboxTests {
    @Test func topBarBrandIconSizeはCaption行高相当() {
        #expect(UsageDisplay.topBarBrandIconSize == 12)
    }

    @Test(arguments: [AgentKind.claudeCode, .codex, .cursor])
    func agentBrandIconFromKindはRegistryDescriptorを使う(kind: AgentKind) {
        let icon = AgentBrandIcon(kind: kind, size: UsageDisplay.topBarBrandIconSize)
        #expect(icon.descriptor.ref.builtinKind == kind)
        #expect(icon.descriptor.displayName == kind.displayName)
    }

    @Test func topBarShortLabelはAutoバケットのラベルをそのまま出す() {
        let bucket = UsageBucket(id: "auto", label: "Auto", usedPercent: 21)
        #expect(UsageDisplay.topBarShortLabel(for: bucket) == "Auto")
    }

    /// バー塗り色は usedPercent に連動（残量 100%＝緑、消費進行で黄→赤）。
    @Test func usageColorは中間帯でも単調に暖色へ遷移する() {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
        }
        #expect(UsageDisplay.usageColor(for: 0) == rgb(90, 200, 130))
        #expect(UsageDisplay.usageColor(for: 52.5) == rgb(165, 195, 105))
        #expect(UsageDisplay.usageColor(for: 100) == rgb(240, 50, 55))
    }
}
