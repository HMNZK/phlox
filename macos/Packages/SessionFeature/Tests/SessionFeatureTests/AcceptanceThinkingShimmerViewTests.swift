import Foundation
import Testing
import AppKit
import QuartzCore
@testable import SessionFeature

// task-1 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-1.md
// 目的: Thinking シマーを SwiftUI TimelineView(30fps) から Core Animation 駆動へ置換し、
//       SwiftUI がタイルのアクセシビリティ木を毎フレーム作り直す病理（複数セッション
//       グリッドでの CPU 暴走・スタックの主犯）を根絶する。シマーの見た目（明度帯が
//       左→右へ流れる、周期 shimmerPeriod=1.6s）と凍結純関数の再利用は維持する。
//
// 手本: DesignSystem/StatusDot.swift の RunningBlinkDot（同じ回帰を CA 化で回避した先例）。
@Suite("Acceptance: Thinking シマーの Core Animation 化（task-1）")
@MainActor
struct AcceptanceThinkingShimmerViewTests {

    /// テストファイル位置を起点に ChatMessageCells+Structured.swift の中身を読む。
    private func structuredCellsSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile
            .deletingLastPathComponent() // .../Tests/SessionFeatureTests
            .deletingLastPathComponent() // .../Tests
            .deletingLastPathComponent() // .../SessionFeature (package root)
            .appendingPathComponent("Sources/SessionFeature/ChatMessageCells+Structured.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test("毎フレーム勾配ビルダー shimmeringThinkingText は除去され CA ビューへ置換されている")
    func perFrameShimmerBuilderRemovedAndReplacedByCAView() throws {
        let source = try structuredCellsSource()
        #expect(
            !source.contains("func shimmeringThinkingText"),
            "毎フレーム 21 ストップの LinearGradient を生成する犯人 shimmeringThinkingText は削除すること"
        )
        #expect(
            source.contains("ThinkingShimmerView"),
            "シマーは Core Animation 駆動の ThinkingShimmerView へ置換すること"
        )
    }

    @Test("シマーは Core Animation の無限反復アニメで周期 shimmerPeriod で回る")
    func shimmerRunsInfiniteCoreAnimationAtShimmerPeriod() throws {
        let host = ThinkingShimmerView.makeHostViewForTesting(
            color: .secondaryLabelColor, scale: 1.0, visible: true
        )
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        host.layoutSubtreeIfNeeded()

        let duration = try #require(
            host.shimmerAnimationDurationForTesting,
            "シマーの反復アニメ（周期）が存在すること"
        )
        #expect(abs(duration - ThinkingAnimationModel.shimmerPeriod) < 1e-6)
        #expect(host.shimmerAnimationRepeatsForeverForTesting)
        #expect(host.isShimmerAnimatingForTesting)
    }

    @Test("非表示ではシマーアニメが停止し、再表示で再開する")
    func shimmerPausesWhenNotVisibleAndResumes() throws {
        let host = ThinkingShimmerView.makeHostViewForTesting(
            color: .secondaryLabelColor, scale: 1.0, visible: false
        )
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        host.layoutSubtreeIfNeeded()
        #expect(
            !host.isShimmerAnimatingForTesting,
            "非表示ではアニメを止めること（オフスクリーンでも CPU/GPU を焼き続けない）"
        )

        host.setVisibleForTesting(true)
        #expect(host.isShimmerAnimatingForTesting, "再表示でアニメを再開すること")
    }

    @Test("帯の明度は凍結 shimmerMinBrightness を下限に有界で、明暗差（bump）を持つ")
    func bandBrightnessBoundedByFrozenFalloff() throws {
        let host = ThinkingShimmerView.makeHostViewForTesting(
            color: .secondaryLabelColor, scale: 1.0, visible: true
        )
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        host.layoutSubtreeIfNeeded()

        let brightnesses = host.shimmerBandBrightnessesForTesting
        #expect(!brightnesses.isEmpty, "帯の明度 stop が構成されていること")

        let minB = ThinkingAnimationModel.shimmerMinBrightness
        for b in brightnesses {
            #expect(!b.isNaN)
            #expect(
                b >= minB - 1e-6 && b <= 1.0 + 1e-6,
                "帯明度は [shimmerMinBrightness, 1.0] に有界（凍結 falloff 由来）"
            )
        }
        let peak = try #require(brightnesses.max())
        let floor = try #require(brightnesses.min())
        #expect(
            peak - floor >= 0.3,
            "帯には実質的な明暗差（bump）がある — 平坦な塗りではなくシマー帯であること"
        )
    }

    @Test("テーマ色の更新がテキスト色へ反映される")
    func colorUpdateReflectsIntoText() throws {
        let host = ThinkingShimmerView.makeHostViewForTesting(
            color: .secondaryLabelColor, scale: 1.0, visible: true
        )
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        host.layoutSubtreeIfNeeded()

        host.updateColorForTesting(.systemRed)
        let applied = try #require(host.appliedTextColorForTesting)
        let a = try #require(applied.usingColorSpace(.sRGB))
        let b = try #require(NSColor.systemRed.usingColorSpace(.sRGB))
        #expect(abs(a.redComponent - b.redComponent) < 0.02)
        #expect(abs(a.greenComponent - b.greenComponent) < 0.02)
        #expect(abs(a.blueComponent - b.blueComponent) < 0.02)
    }
}
