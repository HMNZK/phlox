// フェーズ4（統合検証）用のランタイム視覚アーティファクト（PM 著）。
// 実 DashboardView を NSHostingView でホストし、両サイドバー表示×狭ウィンドウで
// (1) PaneWidthPolicy の onChange 配線が実際に発火して幅がクランプされること
// (2) 右サイドバー（使用量インスペクター）が右端まで見切れず描画されること
// (3) 狭くなった detail でエージェント選択カードが縦積みになること（task-1×task-2 統合）
// を PNG に書き出して確認する。ImageRenderer は onChange/@State の更新ループと
// ScrollView 内容を描画できないため NSHostingView + cacheDisplay を使う。

import AppKit
import AgentDomain
import DesignSystem
import SwiftUI
import PTYKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Suite("Dashboard pane clamp runtime render", .serialized)
struct DashboardPaneClampRuntimeTests {
    @Test @MainActor
    func dashboardView_bothSidebars_writesRuntimeReferencePNGs() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let projectFolder = workspaceRoot.appendingPathComponent("clamp-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        let project = Project(
            name: "Clamp Project",
            directoryPath: projectFolder.path,
            createdAt: Date(timeIntervalSince1970: 5_000),
            isManagedDirectory: false
        )

        let projectStore = InMemoryProjectStore()
        try await projectStore.save([project])
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            projects: projectStore,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [
                .claudeCode: "/usr/local/bin/claude",
                .codex: "/usr/local/bin/codex",
                .cursor: "/usr/local/bin/cursor-agent",
            ]
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let router = AppRouter(viewMode: .single, sidebarVisible: true, inspectorVisible: true)
        router.selectedSession = nil
        router.selectProject(project.id)

        try writePNG(
            viewModel: dashboard, router: router,
            width: 900, height: 700,
            url: URL(fileURLWithPath: "/tmp/dashboard-both-sidebars-900.png")
        )
        try writePNG(
            viewModel: dashboard, router: router,
            width: 1400, height: 800,
            url: URL(fileURLWithPath: "/tmp/dashboard-both-sidebars-1400.png")
        )
    }

    @MainActor
    private func writePNG(
        viewModel: DashboardViewModel,
        router: AppRouter,
        width: CGFloat,
        height: CGFloat,
        url: URL
    ) throws {
        let monitor = UsageMonitor(providers: [:])
        let view = DashboardView(viewModel: viewModel, router: router, usageMonitor: monitor)
            .frame(width: width, height: height)
            .background(DSColor.background)

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
        // onChange(initial:) → @State 更新 → 再レイアウトを反映させるため RunLoop を数周させる
        for _ in 0..<3 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            hosting.layoutSubtreeIfNeeded()
        }

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
        window.orderOut(nil)
    }
}
