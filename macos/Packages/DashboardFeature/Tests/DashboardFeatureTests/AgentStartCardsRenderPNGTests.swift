// フェーズ4（統合検証）用の視覚アーティファクト（PM 著）。
// 実ビュー AgentStartCardsView を NSHostingView + cacheDisplay で描画し、狭幅（縦積み）と
// 十分な幅（横並び）の参照 PNG を /tmp へ書き出す。
// ImageRenderer は macOS で ScrollView 等のプラットフォーム支援ビューの内容を描画しない
// ため使わない（縦積み分岐の ScrollView が空白になり視覚検証にならない）。
// 先例: SessionFeatureTests/ComposerOverflowLayoutTests.writesComposerReferencePNGs

import AppKit
import SwiftUI
import Testing
import AgentDomain
@testable import DashboardFeature

@Suite("AgentStartCards render PNGs", .serialized)
struct AgentStartCardsRenderPNGTests {
    @Test @MainActor
    func agentStartCards_writesReferencePNGs() throws {
        try writePNG(width: 400, height: 720, url: URL(fileURLWithPath: "/tmp/agent-start-cards-narrow.png"))
        try writePNG(width: 800, height: 720, url: URL(fileURLWithPath: "/tmp/agent-start-cards-wide.png"))
    }

    @MainActor
    private func writePNG(width: CGFloat, height: CGFloat, url: URL) throws {
        let view = AgentStartCardsView(
            cards: AgentStartCardsModel.cards(available: [.claudeCode, .codex, .cursor]),
            isCreating: false,
            onSelect: { _, _ in }
        )
        .frame(width: width, height: height)
        .background(Color(nsColor: .windowBackgroundColor))

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // SwiftUI ホスティングのレイアウト反映（GeometryReader→分岐評価）を1周させる
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        hosting.layoutSubtreeIfNeeded()

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
        window.orderOut(nil)
    }
}
