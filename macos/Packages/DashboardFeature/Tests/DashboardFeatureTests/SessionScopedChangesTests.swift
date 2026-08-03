import AppKit
import AgentDomain
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("Session-scoped changes")
struct SessionScopedChangesTests {
    @Test("共有スコープの注記は実際のエディタパネル描画に現れる")
    @MainActor
    func sharedScopeNoticeChangesRenderedPixels() throws {
        let shared = EditorPanelViewModel(
            service: nil,
            changeScope: .shared(repositoryRoot: "/tmp/phlox-scope/repository", peerCount: 1)
        )
        let isolated = EditorPanelViewModel(
            service: nil,
            changeScope: .isolated(repositoryRoot: "/tmp/phlox-scope/repository")
        )

        let sharedImage = try render(shared)
        let isolatedImage = try render(isolated)

        #expect(
            sharedImage != isolatedImage,
            "共有スコープの注記を削除すると、実描画の差分が消える"
        )
    }

    @MainActor
    private func render(_ viewModel: EditorPanelViewModel) throws -> Data {
        let view = EditorPanelView(viewModel: viewModel, topInset: 0)
            .frame(width: 260, height: 300)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: 300)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }

        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let representation = try #require(
            hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        )
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        return try #require(
            representation.representation(using: .png, properties: [:])
        )
    }
}
