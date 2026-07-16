import Testing
import Foundation
import AppKit
import QuartzCore
import SwiftUI
import AgentDomain
@testable import DesignSystem

/// 実行中スピナーを Core Animation 駆動の NSView に置換した修正の回帰を守るテスト。
/// 目的は「SwiftUI の毎フレーム再レイアウト（`.repeatForever`）を二度と持ち込ませない」こと。
/// ビュー自体の見た目は単体テストしづらいため、(1) ソースに `.repeatForever` が無いこと、
/// (2) 生成された NSView が repeatCount=.infinity の回転アニメを持つこと、を検証する。
@Suite @MainActor struct RunningSpinnerTests {
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
            "RunningSpinner は SwiftUI の .repeatForever ではなく Core Animation で回すこと（メインスレッド占有の回帰防止）"
        )
    }

    @Test func spinnerNSViewRunsInfiniteRotation() throws {
        let view = StatusDot(status: .running).makeSpinnerViewForTesting()
        // layout を一度走らせてレイヤーの bounds/position/path を確定させる。
        view.frame = NSRect(x: 0, y: 0, width: 12, height: 12)
        view.layoutSubtreeIfNeeded()

        let shape = try #require(
            view.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first,
            "スピナーの CAShapeLayer が存在すること"
        )
        let animation = try #require(
            shape.animationKeys()?.compactMap { shape.animation(forKey: $0) as? CABasicAnimation }.first,
            "回転アニメ（CABasicAnimation）が追加されていること"
        )
        #expect(animation.keyPath == "transform.rotation.z")
        #expect(animation.repeatCount == .infinity)
        #expect(animation.isRemovedOnCompletion == false)
        #expect(shape.strokeEnd == 0.72)
    }

    /// 旧 SwiftUI Circle().stroke と外径を一致させるため、パスは bounds 全体（inset しない）。
    /// inset していると path の boundingBox が一回り小さくなり、リングが旧版より小さく見える回帰になる。
    @Test func spinnerPathMatchesFullBoundsNoInset() throws {
        let view = StatusDot(status: .running).makeSpinnerViewForTesting()
        view.frame = NSRect(x: 0, y: 0, width: 12, height: 12)
        view.layoutSubtreeIfNeeded()

        let shape = try #require(
            view.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
        )
        let box = try #require(shape.path?.boundingBox)
        // スピナー本体は 11x11 全体。inset していれば 9x9 になる。
        #expect(abs(box.minX) < 0.01)
        #expect(abs(box.minY) < 0.01)
        #expect(abs(box.width - 11) < 0.01)
        #expect(abs(box.height - 11) < 0.01)
    }
}
