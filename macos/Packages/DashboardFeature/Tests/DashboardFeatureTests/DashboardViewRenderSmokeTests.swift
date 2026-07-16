// DashboardView ImageRenderer スモーク（Run 2 / task-6）
// 主要分岐（空状態・サイドバー/詳細・グリッド）の非空描画を固定する。

import AppKit
import AgentDomain
import DesignSystem
import SwiftUI
import PTYKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - Helpers

@MainActor
private func makeRenderDashboard(
    projects: [Project] = [],
    persistedSessions: [PersistedSessionDescriptor] = [],
    workspaceDirectory: URL? = nil
) async throws -> (dashboard: DashboardViewModel, router: AppRouter, workspaceRoot: URL) {
    let workspaceRoot: URL
    if let workspaceDirectory {
        workspaceRoot = workspaceDirectory
    } else {
        workspaceRoot = try makeTemporaryWorkspaceRoot()
    }
    let projectStore = InMemoryProjectStore()
    if !projects.isEmpty {
        try await projectStore.save(projects)
    }

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        projects: projectStore,
        sessions: InMemorySessionStore(persistedSessions),
        workspaceDirectory: workspaceRoot,
        agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"]
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    let router = AppRouter()
    return (dashboard, router, workspaceRoot)
}

@MainActor
private func renderDashboardImage(
    viewModel: DashboardViewModel,
    router: AppRouter,
    width: CGFloat = 1_200,
    height: CGFloat = 800
) throws -> NSImage {
    let monitor = UsageMonitor(providers: [:])
    let renderer = ImageRenderer(
        content: DashboardView(
            viewModel: viewModel,
            router: router,
            usageMonitor: monitor
        )
        .frame(width: width, height: height)
        .background(DSColor.background)
        .environment(\.colorScheme, .dark)
    )
    renderer.scale = 1
    return try #require(renderer.nsImage)
}

private func tiffData(from image: NSImage) throws -> Data {
    try #require(image.tiffRepresentation)
}

// MARK: - Smoke tests

@Test @MainActor
func dashboardViewRender_emptyProjectsDetailState() throws {
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let viewModel = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: URL(fileURLWithPath: "/tmp/phlox-dashboard-render-empty")
        )
    )
    let router = AppRouter()
    let image = try renderDashboardImage(viewModel: viewModel, router: router)

    #expect(try tiffData(from: image).isEmpty == false)
}

@Test @MainActor
func dashboardViewRender_sidebarWithProjectAndSingleSelectEmpty() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let projectFolder = workspaceRoot.appendingPathComponent("render-project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
    let project = Project(
        name: "Render Project",
        directoryPath: projectFolder.path,
        createdAt: Date(timeIntervalSince1970: 1_000),
        isManagedDirectory: false
    )

    let (dashboard, router, _) = try await makeRenderDashboard(
        projects: [project],
        workspaceDirectory: workspaceRoot
    )
    router.viewMode = .single
    router.selectedSession = nil
    router.sidebarVisible = true

    let image = try renderDashboardImage(viewModel: dashboard, router: router)
    #expect(try tiffData(from: image).isEmpty == false)
}

@Test @MainActor
func dashboardViewRender_gridModeWithRestoredSession() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let projectFolder = workspaceRoot.appendingPathComponent("grid-project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
    let project = Project(
        name: "Grid Project",
        directoryPath: projectFolder.path,
        createdAt: Date(timeIntervalSince1970: 2_000),
        isManagedDirectory: false
    )
    let sessionID = SessionID()
    let sessionDirectory = projectFolder
        .appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

    let (dashboard, router, _) = try await makeRenderDashboard(
        projects: [project],
        persistedSessions: [
            makePersistedSessionDescriptor(
                id: sessionID,
                workingDirectory: sessionDirectory.path,
                name: "Grid Session",
                projectID: project.id,
                startedAt: Date(timeIntervalSince1970: 3_000)
            ),
        ],
        workspaceDirectory: workspaceRoot
    )
    router.viewMode = .grid
    router.gridFilterProjectID = project.id
    router.sidebarVisible = true

    let image = try renderDashboardImage(viewModel: dashboard, router: router)
    #expect(try tiffData(from: image).isEmpty == false)
    #expect(!dashboard.filteredGridSessionNodes(projectID: project.id).isEmpty)
}

@Test @MainActor
func dashboardViewRender_majorBranchesProduceDistinctImages() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let emptyViewModel = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceRoot
        )
    )
    let emptyRouter = AppRouter()
    let emptyImage = try renderDashboardImage(viewModel: emptyViewModel, router: emptyRouter)

    let projectFolder = workspaceRoot.appendingPathComponent("compare-project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
    let project = Project(
        name: "Compare Project",
        directoryPath: projectFolder.path,
        createdAt: Date(timeIntervalSince1970: 4_000),
        isManagedDirectory: false
    )
    let (projectDashboard, projectRouter, _) = try await makeRenderDashboard(
        projects: [project],
        workspaceDirectory: workspaceRoot
    )
    projectRouter.viewMode = .single
    projectRouter.selectedSession = nil
    let projectImage = try renderDashboardImage(viewModel: projectDashboard, router: projectRouter)

    #expect(try tiffData(from: emptyImage) != tiffData(from: projectImage))
}
