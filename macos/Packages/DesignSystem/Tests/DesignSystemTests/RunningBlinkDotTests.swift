import Testing
import Foundation
import AppKit
import QuartzCore
import SwiftUI
import AgentDomain
@testable import DesignSystem

/// 実行中インジケータを Core Animation 駆動の点滅ドットに置換した修正の回帰を守るテスト。
/// 目的は「SwiftUI の毎フレーム再レイアウト（`.repeatForever`）を二度と持ち込ませない」こと。
/// ビュー自体の見た目は単体テストしづらいため、(1) ソースに `.repeatForever` が無いこと、
/// (2) 生成された NSView が repeatCount=.infinity の透明度点滅アニメを持つこと、を検証する。
@Suite @MainActor struct RunningBlinkDotTests {
    /// テストファイルの位置を起点に StatusDot.swift の中身を読む。
    private func statusDotSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile
            .deletingLastPathComponent() // .../Tests/DesignSystemTests
            .deletingLastPathComponent() // .../Tests
            .deletingLastPathComponent() // .../DesignSystem (package root)
            .appendingPathComponent("Sources/DesignSystem/StatusDot.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test func statusDotSourceHasNoRepeatForeverModifier() throws {
        let source = try statusDotSource()
        #expect(
            !source.contains(".repeatForever"),
            "実行中インジケータは SwiftUI の .repeatForever ではなく Core Animation で回すこと（メインスレッド占有の回帰防止）"
        )
    }

    @Test func blinkDotNSViewRunsInfiniteOpacityPulse() throws {
        let view = StatusDot(status: .running).makeBlinkDotViewForTesting()
        // layout を一度走らせてレイヤーの bounds/position/path を確定させる。
        view.frame = NSRect(x: 0, y: 0, width: 12, height: 12)
        view.layoutSubtreeIfNeeded()

        let dot = try #require(
            view.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first,
            "点滅ドットの CAShapeLayer が存在すること"
        )
        let animation = try #require(
            dot.animationKeys()?.compactMap { dot.animation(forKey: $0) as? CABasicAnimation }.first,
            "点滅アニメ（CABasicAnimation）が追加されていること"
        )
        #expect(animation.keyPath == "opacity")
        #expect(animation.repeatCount == .infinity)
        #expect(animation.autoreverses)
        #expect(animation.isRemovedOnCompletion == false)
    }

    /// 静的な状態ドット（Circle 8x8）と同径で描くことを固定する。
    /// 径がずれると実行中ドットだけ大きさが違って見える回帰になる。
    @Test func blinkDotPathIs8x8() throws {
        let view = StatusDot(status: .running).makeBlinkDotViewForTesting()
        view.frame = NSRect(x: 0, y: 0, width: 12, height: 12)
        view.layoutSubtreeIfNeeded()

        let dot = try #require(
            view.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
        )
        let box = try #require(dot.path?.boundingBox)
        #expect(abs(box.minX) < 0.01)
        #expect(abs(box.minY) < 0.01)
        #expect(abs(box.width - 8) < 0.01)
        #expect(abs(box.height - 8) < 0.01)
    }
}
