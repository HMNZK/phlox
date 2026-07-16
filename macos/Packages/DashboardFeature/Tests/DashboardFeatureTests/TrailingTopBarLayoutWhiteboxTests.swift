import Foundation
import Testing
@testable import DashboardFeature

// task-4 白箱テスト（実装役著述）。
// 契約: TrailingTopBarLayout.usageAvailableWidth の名指しハザード
// （負値クランプ・二重差し引き・実測幅増加時の単調減少）を純関数経路で捕まえる。

@Suite("TrailingTopBarLayout whitebox")
struct TrailingTopBarLayoutWhiteboxTests {

    @Test
    func subtractsEachOccupiedComponentIndependently() {
        let baseline = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 900,
            occupiedSidebarWidth: 0,
            measuredControlsWidth: 100,
            spacing: 8,
            trailingPadding: 12
        )
        let widerSidebar = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 900,
            occupiedSidebarWidth: 50,
            measuredControlsWidth: 100,
            spacing: 8,
            trailingPadding: 12
        )
        let widerControls = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 900,
            occupiedSidebarWidth: 0,
            measuredControlsWidth: 150,
            spacing: 8,
            trailingPadding: 12
        )
        #expect(baseline - widerSidebar == 50)
        #expect(baseline - widerControls == 50)
    }

    @Test
    func clampsNegativeResultsToZero() {
        let width = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 100,
            occupiedSidebarWidth: 80,
            measuredControlsWidth: 80,
            spacing: 8,
            trailingPadding: 12
        )
        #expect(width == 0)
    }

    @Test
    func decreasesMonotonicallyAsControlsGrow() {
        let widths = [80, 120, 200, 360].map { controlsWidth in
            TrailingTopBarLayout.usageAvailableWidth(
                windowWidth: 1_000,
                occupiedSidebarWidth: 0,
                measuredControlsWidth: CGFloat(controlsWidth),
                spacing: 8,
                trailingPadding: 12
            )
        }
        for index in 1 ..< widths.count {
            #expect(widths[index] < widths[index - 1])
        }
    }

    @Test
    func ignoresHiddenSidebarWidth() {
        let hidden = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 700,
            occupiedSidebarWidth: 0,
            measuredControlsWidth: 90,
            spacing: 8,
            trailingPadding: 12
        )
        let visible = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 700,
            occupiedSidebarWidth: 280,
            measuredControlsWidth: 90,
            spacing: 8,
            trailingPadding: 12
        )
        #expect(hidden - visible == 280)
    }

    @Test
    func spacingAndPaddingReduceAvailableWidth() {
        let withoutGutters = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 500,
            occupiedSidebarWidth: 0,
            measuredControlsWidth: 100,
            spacing: 0,
            trailingPadding: 0
        )
        let withGutters = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 500,
            occupiedSidebarWidth: 0,
            measuredControlsWidth: 100,
            spacing: 8,
            trailingPadding: 12
        )
        #expect(withoutGutters - withGutters == 20)
    }

    @Test
    func acceptanceScenarioWideControlsMatchesExplicitCGFloatRHS() {
        let wideControls = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 1_000,
            occupiedSidebarWidth: 0,
            measuredControlsWidth: 390,
            spacing: 8,
            trailingPadding: 12
        )
        #expect(wideControls == CGFloat(1_000 - 390 - 8 - 12))
    }

    @Test
    func usesConservativeControlsEstimateBeforeMeasurement_notZero() {
        let single = TrailingTopBarLayout.effectiveControlsWidth(
            measured: 0,
            hasMeasured: false,
            viewMode: .single
        )
        let team = TrailingTopBarLayout.effectiveControlsWidth(
            measured: 0,
            hasMeasured: false,
            viewMode: .team
        )
        let grid = TrailingTopBarLayout.effectiveControlsWidth(
            measured: 0,
            hasMeasured: false,
            viewMode: .grid
        )
        #expect(single == 200)
        #expect(team == 200)
        #expect(grid == 320)
        #expect(single > 0)
        #expect(grid > 0)
    }

    @Test
    func zeroWidthMeasurementIsIgnored() {
        let unchanged = TrailingTopBarLayout.applyWidthMeasurement(
            newWidth: 0,
            currentMeasured: 140,
            hasMeasured: true
        )
        #expect(unchanged.measured == 140)
        #expect(unchanged.hasMeasured == true)

        let beforeFirstMeasure = TrailingTopBarLayout.applyWidthMeasurement(
            newWidth: 0,
            currentMeasured: 0,
            hasMeasured: false
        )
        #expect(beforeFirstMeasure.measured == 0)
        #expect(beforeFirstMeasure.hasMeasured == false)
    }

    @Test
    func viewModeChangeResetsToConservativeThenRemeasuresSameWidth() {
        let conservative = TrailingTopBarLayout.effectiveControlsWidth(
            measured: 140,
            hasMeasured: false,
            viewMode: .team
        )
        #expect(conservative == 200)

        let remeasured = TrailingTopBarLayout.applyWidthMeasurement(
            newWidth: 140,
            currentMeasured: 140,
            hasMeasured: false
        )
        #expect(remeasured.hasMeasured == true)
        #expect(remeasured.measured == 140)

        let confirmed = TrailingTopBarLayout.effectiveControlsWidth(
            measured: remeasured.measured,
            hasMeasured: remeasured.hasMeasured,
            viewMode: .team
        )
        #expect(confirmed == 140)
    }

    @Test
    func leadingOverlayWidthIncludedInOccupiedSidebar() {
        let leadingWidth = TrailingTopBarLayout.conservativeLeadingOverlayWidthEstimate()
        let withoutLeading = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 900,
            occupiedSidebarWidth: 0,
            measuredControlsWidth: 140,
            spacing: 8,
            trailingPadding: 12
        )
        let withLeading = TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: 900,
            occupiedSidebarWidth: leadingWidth,
            measuredControlsWidth: 140,
            spacing: 8,
            trailingPadding: 12
        )
        #expect(withoutLeading - withLeading == leadingWidth)
    }

    @Test
    func occupiedWidthForUsageLayoutAggregatesSidebarAndLeading() {
        let leading = TrailingTopBarLayout.effectiveLeadingOverlayWidth(
            measured: 200,
            hasMeasured: true
        )
        let visible = TrailingTopBarLayout.occupiedWidthForUsageLayout(
            sidebarWidth: 280,
            sidebarVisible: true,
            leadingOverlayWidth: leading
        )
        let hidden = TrailingTopBarLayout.occupiedWidthForUsageLayout(
            sidebarWidth: 280,
            sidebarVisible: false,
            leadingOverlayWidth: leading
        )
        #expect(visible == 480)
        #expect(hidden == 200)
    }

    @Test
    func usesConservativeLeadingEstimateBeforeMeasurement() {
        let estimate = TrailingTopBarLayout.effectiveLeadingOverlayWidth(
            measured: 0,
            hasMeasured: false
        )
        #expect(estimate == TrailingTopBarLayout.conservativeLeadingOverlayWidthEstimate())
        #expect(estimate == 470)
    }
}
