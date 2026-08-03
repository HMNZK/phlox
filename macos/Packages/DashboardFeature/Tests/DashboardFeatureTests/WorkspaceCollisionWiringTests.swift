import AppKit
import Foundation
import SwiftUI
import Testing
import AgentDomain
import DesignSystem
import HookServer
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

@Suite("Workspace collision wiring (task-1)")
struct WorkspaceCollisionWiringTests {
    @Test @MainActor
    func sessionExposesRawWorkspacePathWithoutChangingDisplayPath() async throws {
        let ptyManager = MockPTYManager()
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        ))
        await dashboard.start()

        let projectID = try #require(dashboard.addProject(
            name: "Project",
            directoryPath: projectURL.path
        ))
        let sessionID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID
        )
        let session = try #require(dashboard.sessions.first { $0.id == sessionID })

        #expect(session.rawWorkspacePath == projectURL.path)
        #expect(session.workspacePath == (projectURL.path as NSString).abbreviatingWithTildeInPath)
    }

    @Test @MainActor
    func dashboardDerivesCollisionGroupsFromActiveSessions() async throws {
        let ptyManager = MockPTYManager()
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

        let projectURL = workspaceURL.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        ))
        await dashboard.start()

        let projectID = try #require(dashboard.addProject(
            name: "Shared",
            directoryPath: projectURL.path
        ))
        let firstID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID
        )
        let secondID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID
        )

        #expect(dashboard.workspaceCollisions.count == 1)
        #expect(dashboard.workspaceCollisionSessionIDs == Set([firstID, secondID]))
    }

    @Test("衝突する 2 セッションのサイドバー描画に共有警告が現れる")
    @MainActor
    func dashboardSidebarRender_sharedWorkspaceWarningChangesPixels() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let projectURL = workspaceRoot.appendingPathComponent("project", isDirectory: true)
        let sharedURL = projectURL.appendingPathComponent("shared", isDirectory: true)
        let firstURL = projectURL.appendingPathComponent("first", isDirectory: true)
        let secondURL = projectURL.appendingPathComponent("second", isDirectory: true)
        for directory in [projectURL, sharedURL, firstURL, secondURL] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let projectID = ProjectID()
        let project = Project(
            id: projectID,
            name: "Shared Project",
            directoryPath: projectURL.path,
            createdAt: Date(timeIntervalSince1970: 10_000),
            isManagedDirectory: false
        )
        let firstID = SessionID()
        let secondID = SessionID()
        let startedAt = Date(timeIntervalSince1970: 20_000)

        let collidingSessions = [
            makePersistedSessionDescriptor(
                id: firstID,
                workingDirectory: sharedURL.path,
                name: "First Session",
                projectID: projectID,
                startedAt: startedAt
            ),
            makePersistedSessionDescriptor(
                id: secondID,
                workingDirectory: sharedURL.path,
                name: "Second Session",
                projectID: projectID,
                startedAt: startedAt
            ),
        ]
        let nonCollidingSessions = [
            makePersistedSessionDescriptor(
                id: firstID,
                workingDirectory: firstURL.path,
                name: "First Session",
                projectID: projectID,
                startedAt: startedAt
            ),
            makePersistedSessionDescriptor(
                id: secondID,
                workingDirectory: secondURL.path,
                name: "Second Session",
                projectID: projectID,
                startedAt: startedAt
            ),
        ]

        let (collidingImageData, collidingIDs) = try await renderWorkspaceCollisionSidebar(
            project: project,
            persistedSessions: collidingSessions,
            expectedCollisionIDs: Set([firstID, secondID]),
            workspaceDirectory: workspaceRoot
        )
        let (nonCollidingImageData, nonCollidingIDs) = try await renderWorkspaceCollisionSidebar(
            project: project,
            persistedSessions: nonCollidingSessions,
            expectedCollisionIDs: [],
            workspaceDirectory: workspaceRoot
        )

        #expect(collidingIDs == Set([firstID, secondID]))
        #expect(nonCollidingIDs.isEmpty)
        #expect(
            collidingImageData != nonCollidingImageData,
            "衝突する同一構成のセッション行と、衝突しない同一構成のセッション行は描画結果が異なる"
        )
    }

    @Test("共有警告の表示規則は色以外の情報を持つ")
    func workspaceCollisionWarningPresentationHasAccessibleIdentity() {
        #expect(WorkspaceCollisionWarningPresentation.symbolName == "exclamationmark.triangle.fill")
        #expect(WorkspaceCollisionWarningPresentation.accessibilityLabel == "作業ディレクトリを共有中")
        #expect(WorkspaceCollisionWarningPresentation.accessibilityIdentifier == "workspace-collision-warning")
    }
}

@MainActor
private func renderWorkspaceCollisionSidebar(
    project: Project,
    persistedSessions: [PersistedSessionDescriptor],
    expectedCollisionIDs: Set<SessionID>,
    workspaceDirectory: URL
) async throws -> (imageData: Data, collisionIDs: Set<SessionID>) {
    let projectStore = InMemoryProjectStore()
    try await projectStore.save([project])
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(environment: makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        projects: projectStore,
        sessions: InMemorySessionStore(persistedSessions),
        workspaceDirectory: workspaceDirectory,
        agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"]
    ))
    await dashboard.start()

    #expect(dashboard.sessions.count == persistedSessions.count)
    #expect(dashboard.workspaceCollisionSessionIDs == expectedCollisionIDs)

    let router = AppRouter()
    let sidebar = DashboardSidebarView(
        viewModel: dashboard,
        router: router,
        expandedProjectIDs: .constant([project.id]),
        draftName: .constant(""),
        renamingProject: .constant(nil as Project?),
        pendingProjectDeletion: .constant(nil as Project?),
        renamingSession: .constant(nil as SelectedSessionNode?),
        pendingDeletion: .constant(nil as SelectedSessionNode?),
        pendingWorkspaceChange: .constant(nil as SessionViewModel?),
        sessionTreeViewModel: .constant(SessionTreeViewModel()),
        onChooseProjectDirectory: {},
        onMoveSessionToProject: { _, _ in },
        newSessionMenuItems: { _ in EmptyView() }
    )
    let view = sidebar
        .frame(width: 280, height: 240, alignment: .topLeading)
        .background(DSColor.background)
        .environment(\.colorScheme, .dark)
    let imageData = try renderWorkspaceCollisionSidebarImage(from: view)
    return (imageData, dashboard.workspaceCollisionSessionIDs)
}

@MainActor
private func renderWorkspaceCollisionSidebarImage<V: View>(from view: V) throws -> Data {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 240)
    let window = NSWindow(
        contentRect: hosting.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hosting
    defer {
        // `isReleasedWhenClosed` の既定は true で、`close()` が NSWindow 自身を release する。
        // ARC 下ではローカル変数 `window` も強参照を持つため、そのまま閉じると二重解放になり
        // `objc_autoreleasePoolPop` で SIGSEGV する（実測で再現）。**この 1 行を消さないこと。**
        window.isReleasedWhenClosed = false
        window.close()
    }
    hosting.layoutSubtreeIfNeeded()
    hosting.displayIfNeeded()
    let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    let imageData = try #require(rep.representation(using: .png, properties: [:]))
    return imageData
}
