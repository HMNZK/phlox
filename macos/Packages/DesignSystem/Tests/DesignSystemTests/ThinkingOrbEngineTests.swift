import AgentDomain
import Foundation
import Testing
@testable import DesignSystem

@Suite struct ThinkingOrbPresetTests {
    @Test func everyStateResolvesToItsOwnMode() {
        let modes = AgentActivityState.allCases.map { $0.orbMode }
        #expect(Set(modes).count == AgentActivityState.allCases.count)
    }

    @Test func inlinePresetUsesFewerAndLargerDotsThanLarge() {
        let large = OrbPresets.resolve(state: .searching, size: .large)
        let inline = OrbPresets.resolve(state: .searching, size: .inline)
        #expect(large.mode == .globe)
        #expect(inline.mode == .globe)
        // count 倍率 0.42 → 0.105 なので格子は粗く、size 倍率 1.15 → 1.75 なので点は大きい。
        #expect((inline.options.latRings ?? 0) < (large.options.latRings ?? 0))
        #expect((inline.options.rBase ?? 0) > (large.options.rBase ?? 0))
    }

    @Test func countScalingSplitsAcrossLatticeSidesAndKeepsFloors() {
        let scaled = OrbProfiles.scaleCounts(OrbProfiles.base(.globe), by: 0.105)
        // 17 * √0.105 ≒ 5.5 → 6、44 * √0.105 ≒ 14.3 → 14
        #expect(scaled.latRings == 6)
        #expect(scaled.lonDensity == 14)
        // 総点数はおおむね scale 倍（各辺 √scale）
        let scaledTotal: Double = 6 * 14
        let baseTotal: Double = 17 * 44
        let ratio: Double = scaledTotal / baseTotal
        #expect(abs(ratio - 0.105) < 0.02)
    }

    @Test func countScalingNeverDropsBelowFloor() {
        let scaled = OrbProfiles.scaleCounts(OrbProfiles.base(.orbits), by: 0.0001)
        #expect(scaled.orbitN == 1)
        #expect(scaled.ghostN == 1)
    }

    @Test func radiusScalingMultipliesEveryRadiusKey() {
        let scaled = OrbProfiles.scaleRadii(OrbProfiles.base(.rubik), by: 2)
        #expect(scaled.rBase == 1.2)
        #expect(scaled.rDepth == 3.4)
        #expect(scaled.rActive == 0.6)
        // 個数系は半径スケールで変わらない
        #expect(scaled.latRings == 15)
    }
}

@Suite struct ThinkingOrbRendererTests {
    private func dots(_ state: AgentActivityState, time: Double, size: OrbSizePreset = .inline) -> [OrbDot] {
        let preset = OrbPresets.resolve(state: state, size: size)
        return OrbModeRenderer.dots(
            mode: preset.mode,
            size: Double(size.rawValue),
            time: time,
            options: preset.options
        )
    }

    @Test(arguments: AgentActivityState.allCases)
    func everyStateProducesDotsInsideTheFrame(state: AgentActivityState) {
        let frame = 20.0
        let produced = dots(state, time: 1.234)
        #expect(!produced.isEmpty)
        for dot in produced {
            #expect(dot.r > 0)
            #expect(dot.alpha <= 1.0001)
            // 点は枠の周辺 ±25% に収まる（枠外へ飛ぶ座標バグの検出）
            #expect(dot.x > -frame * 0.25 && dot.x < frame * 1.25)
            #expect(dot.y > -frame * 0.25 && dot.y < frame * 1.25)
        }
    }

    @Test(arguments: AgentActivityState.allCases)
    func renderingIsDeterministic(state: AgentActivityState) {
        #expect(dots(state, time: 2.5) == dots(state, time: 2.5))
    }

    @Test(arguments: AgentActivityState.allCases)
    func framesAdvanceOverTime(state: AgentActivityState) {
        // 静止していない＝時刻が違えば点群も違う
        #expect(dots(state, time: 0.5) != dots(state, time: 1.9))
    }

    @Test func morphDotCountFollowsIconDensity() {
        let preset = OrbPresets.resolve(state: .editing, size: .inline)
        let produced = OrbModeRenderer.dots(mode: .morph, size: 20, time: 0.3, options: preset.options)
        // n = max(6, round(34 * iconD))
        let expected = max(6, Int((34 * (preset.options.iconD ?? 1)).rounded()))
        #expect(produced.count == expected)
    }
}

@Suite @MainActor struct ThinkingOrbHostViewTests {
    @Test func displayLinkRunsOnlyWhileAnimating() {
        let view = ThinkingOrbHostView.makeForTesting(state: .thinking, size: .inline, isAnimating: true, dark: true)
        #expect(view.isDisplayLinkRunningForTesting)

        view.setAnimatingForTesting(false)
        #expect(!view.isDisplayLinkRunningForTesting)

        view.setAnimatingForTesting(true)
        #expect(view.isDisplayLinkRunningForTesting)

        view.stopDisplayLink()
        #expect(!view.isDisplayLinkRunningForTesting)
    }

    @Test func pausedViewDrawsTheStaticRepresentativeFrame() {
        let view = ThinkingOrbHostView.makeForTesting(state: .searching, size: .inline, isAnimating: false, dark: true)
        #expect(view.frameTimeForTesting(now: 1_000) == ThinkingOrbHostView.staticFrameTime)
        #expect(view.frameTimeForTesting(now: 2_000) == ThinkingOrbHostView.staticFrameTime)
    }

    @Test func animatingViewScalesTheSharedClockByThePresetSpeed() {
        let view = ThinkingOrbHostView.makeForTesting(state: .searching, size: .inline, isAnimating: true, dark: true)
        let speed = view.resolvedPresetForTesting.speed
        #expect(view.frameTimeForTesting(now: 3) == 3 * speed)
        view.stopDisplayLink()
    }

    @Test func stateChangeSwitchesTheResolvedMode() {
        let view = ThinkingOrbHostView.makeForTesting(state: .thinking, size: .inline, isAnimating: false, dark: true)
        #expect(view.resolvedPresetForTesting.mode == .orbits)
        view.update(state: .writing, size: .inline, isAnimating: false, dark: true)
        #expect(view.resolvedPresetForTesting.mode == .ribbon)
    }
}
