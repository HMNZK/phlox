import Foundation
import AppKit
import SwiftUI
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

@MainActor @Suite("GridAutoLayout")
struct GridAutoLayoutTests {
    final class OffscreenGridWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }
    let viewport = CGSize(width: 1643, height: 903)

    func snapshot(_ count: Int) -> DashboardRuntimeSnapshot {
        .init(projects: [], sessions: (0..<count).map { index in
            .chat(SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(timeIntervalSince1970: Double(index)), agentRef: .builtin(.codex), workingDirectory: "/runtime"))
        }, availableAgentKinds: [])
    }

    func dashboard(_ snapshot: DashboardRuntimeSnapshot) throws -> DashboardViewModel {
        try DashboardViewModel(projection: snapshot) { _ in .none }
    }

    @Test func defaultAutomaticAndInvalidActionsDoNotChangeMode() throws {
        let vm = try dashboard(snapshot(3))
        #expect(vm.gridLayoutState == .automatic(previousCustom: nil))
        let before = vm.gridLayoutForDisplay(in: viewport)
        vm.handlePaneLayoutAction(.swap(SessionID(), SessionID()), in: viewport)
        vm.handlePaneLayoutAction(.equalize(PaneID("unknown")), in: viewport)
        #expect(vm.gridLayoutState == .automatic(previousCustom: nil))
        #expect(vm.gridLayoutForDisplay(in: viewport) == before)
        vm.handlePaneLayoutAction(.applyPreset(.balanced), in: viewport)
        #expect(!vm.gridLayoutState.isAutomatic)
    }

    @Test func filteredAutomaticDividerMaterializesWithoutChangingOtherVisibleProportions() throws {
        let vm = try dashboard(snapshot(5))
        let visible = Set(vm.sessionNodes.prefix(2).map(\.id))
        vm.gridSessionSelection = visible
        let before = vm.gridLayoutForDisplay(in: viewport)
        let divider = try #require(before.tree.frames(in: before.canvasSize, spacing: 8).dividers.first)
        vm.handlePaneLayoutAction(.setDivider(divider.id, leadingFraction: 0.65), in: viewport)
        #expect(!vm.gridLayoutState.isAutomatic)
        #expect(Set(vm.paneLayout.sessions) == Set(vm.sessionNodes.map(\.id)))
        #expect(vm.paneLayoutForDisplay(in: viewport) == before.tree.settingDivider(divider.id, leadingFraction: 0.65))
        let custom = vm.gridLayoutState
        vm.gridSessionSelection = nil
        vm.gridSessionSelection = visible
        #expect(vm.gridLayoutState == custom)
    }

    @Test func automaticRestoreAndUndoPreserveCustomCanvasAcrossRuntimeChanges() throws {
        var source = snapshot(7)
        let vm = try dashboard(source)
        let small = CGSize(width: 1088, height: 500)
        vm.handlePaneLayoutAction(.applyPreset(.columns2), in: small)
        let custom = try #require(vm.gridLayoutState.customLayout)
        #expect(custom.canvasMinimum.height > small.height)
        vm.restoreAutomaticGridLayout()
        vm.restoreAutomaticGridLayout()
        #expect(vm.canUndoAutomaticGridLayout)
        source.sessions.removeLast()
        let added = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(), agentRef: .builtin(.codex), workingDirectory: "/runtime")
        source.sessions.append(.chat(added))
        try vm.applyRuntimeSnapshot(source)
        vm.undoAutomaticGridLayout()
        #expect(!vm.gridLayoutState.isAutomatic)
        #expect(vm.gridLayoutState.customLayout?.canvasMinimum == custom.canvasMinimum)
        #expect(Set(vm.paneLayout.sessions) == Set(source.sessions.map(\.id)))
        #expect(!vm.canUndoAutomaticGridLayout)
        vm.restoreAutomaticGridLayout()
        vm.handlePaneLayoutAction(.swap(vm.sessionNodes[0].id, vm.sessionNodes[1].id), in: viewport)
        #expect(!vm.canUndoAutomaticGridLayout)
    }

    @Test func newRuntimeSessionsJoinExplicitSelectionExceptInternalSessions() throws {
        var source = snapshot(2)
        let vm = try dashboard(source)
        vm.gridSessionSelection = [source.sessions[0].id]
        let normal = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(), agentRef: .builtin(.codex), workingDirectory: "/runtime")
        var internalSession = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(), agentRef: .builtin(.codex), workingDirectory: "/runtime")
        internalSession.parentSessionID = source.sessions[0].id
        internalSession.launchContext = .orchestration
        source.sessions += [.chat(normal), .chat(internalSession)]
        try vm.applyRuntimeSnapshot(source)
        #expect(vm.gridSessionSelection == Set([source.sessions[0].id, normal.id]))
        #expect(Set(vm.paneLayoutForDisplay(in: viewport).sessions) == vm.gridSessionSelection)
    }

    @Test func automaticUsesProjectAndParentChildOrderAndIgnoresStatus() throws {
        let a = Project(name: "A", directoryPath: "/a", createdAt: Date(), isManagedDirectory: false)
        let b = Project(name: "B", directoryPath: "/b", createdAt: Date(), isManagedDirectory: false)
        func entry(_ project: ProjectID?, parent: SessionID? = nil, internalChild: Bool = false) -> SessionRuntimeChatSnapshot {
            var value = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(), agentRef: .builtin(.codex), workingDirectory: "/runtime")
            value.projectID = project
            value.parentSessionID = parent
            value.launchContext = internalChild ? .orchestration : .interactive
            return value
        }
        let parent = entry(a.id)
        let sibling = entry(a.id)
        let child = entry(a.id, parent: parent.id)
        let nested = entry(a.id, parent: child.id, internalChild: true)
        let other = entry(b.id)
        let unassigned = entry(nil)
        var source = DashboardRuntimeSnapshot(projects: [a, b], sessions: [unassigned, other, parent, sibling, child, nested].map { .chat($0) }, availableAgentKinds: [])
        let vm = try dashboard(source)
        #expect(vm.gridTileOrder(in: viewport) == [parent.id, child.id, nested.id, sibling.id, other.id, unassigned.id])
        vm.gridSessionFilterProjectID = a.id
        #expect(vm.gridTileOrder(in: viewport) == [parent.id, child.id, nested.id, sibling.id])
        let before = vm.gridLayoutForDisplay(in: viewport)
        if case .chat(var updated) = source.sessions[2] { updated.status = .running; source.sessions[2] = .chat(updated) }
        try vm.applyRuntimeSnapshot(source)
        #expect(vm.gridLayoutForDisplay(in: viewport) == before)
    }

    @Test func viewportsFreezeIndependentlyAndRejectInvalidGeometry() throws {
        let vm = try dashboard(snapshot(6))
        let wide = GridViewport(), narrow = GridViewport()
        wide.update(viewport)
        narrow.update(CGSize(width: 1088, height: 500))
        let wideBefore = vm.gridLayoutForDisplay(in: wide.size)
        wide.liveResizeChanged(true)
        wide.update(CGSize(width: 700, height: 600))
        #expect(vm.gridLayoutForDisplay(in: wide.size) == wideBefore)
        let narrowBefore = vm.gridLayoutForDisplay(in: narrow.size)
        wide.liveResizeChanged(false)
        #expect(wide.size == CGSize(width: 700, height: 600))
        #expect(vm.gridLayoutForDisplay(in: narrow.size) == narrowBefore)
        narrow.update(CGSize(width: CGFloat.nan, height: 2))
        narrow.update(.zero)
        #expect(vm.gridLayoutForDisplay(in: narrow.size) == narrowBefore)
    }

    @Test func twoHostedGridsKeepTheirOwnViewportDuringLiveResize() async throws {
        let vm = try dashboard(snapshot(6))
        let router = AppRouter()
        router.viewMode = .grid
        let wide = GridViewport(), narrow = GridViewport()
        func host(width: CGFloat, viewport: GridViewport) -> NSWindow {
            let view = DashboardDetailView(viewModel: vm, router: router, newChatDraftStore: NewChatDraftStore(),
                pendingDeletion: .constant(nil), onRenameSession: { _ in }, pendingWorkspaceChange: .constant(nil),
                onNewChatLaunchFailure: { _, _ in }, gridViewport: viewport)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width + 16, height: 915), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.contentView?.layoutSubtreeIfNeeded()
            return window
        }
        let first = host(width: 1643, viewport: wide), second = host(width: 1088, viewport: narrow)
        defer { first.contentView = nil; second.contentView = nil; first.close(); second.close() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(wide.size.width == 1643)
        #expect(narrow.size.width == 1088)
        let firstBefore = vm.gridLayoutForDisplay(in: wide.size)
        let secondBefore = vm.gridLayoutForDisplay(in: narrow.size)
        NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: first)
        first.setContentSize(NSSize(width: 716, height: 915))
        first.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.gridLayoutForDisplay(in: wide.size) == firstBefore)
        #expect(vm.gridLayoutForDisplay(in: narrow.size) == secondBefore)
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: first)
        #expect(wide.size.width == 700)
        #expect(vm.gridLayoutForDisplay(in: narrow.size) == secondBefore)
    }

    @Test func commandAndTileCloseUseSameDrawnOrder() async throws {
        _ = NSApplication.shared
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }
        var source = snapshot(7)
        let project = Project(name: "Grid", directoryPath: "/runtime", createdAt: Date(), isManagedDirectory: false)
        source.projects = [project]
        source.sessions = source.sessions.map { entry in
            guard case .chat(var chat) = entry else { return entry }
            chat.projectID = project.id
            return .chat(chat)
        }
        let vm = try dashboard(source)
        let ids = source.sessions.map(\.id)
        vm.handlePaneLayoutAction(.swap(ids[0], ids[1]), in: viewport)
        let router = AppRouter(selectedSession: ids[3])
        router.selectedProjectID = project.id
        router.viewMode = .grid
        router.inspectorVisible = false
        let viewport = GridViewport()
        let host = NSHostingView(rootView: DashboardView(viewModel: vm, router: router,
            usageMonitor: UsageMonitor(providers: [:]), initialSidebarWidth: 260, gridViewport: viewport))
        let window = OffscreenGridWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1920, height: 1100), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let extraHeight = 2000 - viewport.size.height
        window.setContentSize(NSSize(width: 1920, height: host.bounds.height + extraHeight))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewport.size == CGSize(width: 1643, height: 2000))
        #expect(vm.gridTileOrder(in: viewport.size) == [ids[1], ids[0], ids[2], ids[4], ids[5], ids[3], ids[6]])
        #expect(router.requestClose())
        try await Task.sleep(for: .milliseconds(100))
        #expect(router.selectedSession == ids[6])
        #expect(!vm.paneLayoutForDisplay(in: viewport.size).sessions.contains(ids[3]))
        vm.gridSessionSelection = nil
        router.selectedSession = ids[3]
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let tile = try #require(IntegrationFixAccessibility.find("grid-tile-\(ids[3].rawValue.uuidString)", in: host))
        func closeButton(_ object: NSObject) -> NSObject? {
            if (object as AnyObject).accessibilityRole() == NSAccessibility.Role.button,
               (object as AnyObject).accessibilityLabel() == "グリッドから外す" { return object }
            return ((object as AnyObject).accessibilityChildren() as? [NSObject] ?? []).lazy.compactMap(closeButton).first
        }
        let close = try #require(closeButton(tile))
        #expect((close as AnyObject).accessibilityPerformPress())
        try await Task.sleep(for: .milliseconds(100))
        #expect(router.selectedSession == ids[6])
        #expect(!vm.paneLayoutForDisplay(in: viewport.size).sessions.contains(ids[3]))
    }

    @Test func customAndAutomaticStateRoundTripAndLegacyMigration() throws {
        let suite = "grid-auto-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PaneLayoutStore(userDefaults: defaults)
        #expect(store.loadState() == .automatic(previousCustom: nil))
        let tree = PaneLayoutPreset.columns2.tree(for: [SessionID(), SessionID()])
        store.save(tree)
        store.savePresetState(.init(preset: .columns2, isAdjusted: true))
        let legacy = CustomGridLayout(tree: tree, presetState: .init(preset: .columns2, isAdjusted: true))
        #expect(store.loadState() == .custom(legacy))
        var custom = legacy
        custom.canvasMinimum = CGSize(width: 1643, height: 1336)
        for state: GridLayoutState in [.custom(custom), .automatic(previousCustom: custom), .automatic(previousCustom: nil)] {
            store.saveState(state)
            #expect(store.loadState() == state)
        }
        for broken in ["{}", "{\"schemaVersion\":99,\"state\":{}}", "{\"schemaVersion\":1,\"mode\":\"custom\"}"] {
            defaults.set(Data(broken.utf8), forKey: PaneLayoutStore.stateStorageKey)
            #expect(store.loadState() == .automatic(previousCustom: nil), "壊れた新形式を旧ツリーへ読み替えない")
        }
        defaults.removeObject(forKey: PaneLayoutStore.stateStorageKey)
        defaults.set(Data("{\"schemaVersion\":99}".utf8), forKey: PaneLayoutStore.storageKey)
        #expect(store.loadState() == .automatic(previousCustom: nil))
    }
}
