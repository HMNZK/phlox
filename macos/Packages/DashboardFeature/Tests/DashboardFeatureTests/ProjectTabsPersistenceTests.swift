import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

@Suite @MainActor struct ProjectTabsPersistenceTests {
    @Test(arguments: [ProjectTab.terminal(TerminalTabID()), .browser, .simulator])
    func transientPaneIsRemovedOnEitherSide(_ transient: ProjectTab) throws {
        let suite = "phlox.projectTabs.panes.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        let store = ProjectTabStore(defaults: defaults)
        for transientOnLeft in [false, true] {
            store.updateLayout(for: project) {
                $0.open(.changes); $0.open(transient)
                $0.left = transientOnLeft ? transient : .changes
                $0.right = transientOnLeft ? .changes : transient
                $0.focusesRight = true
            }
            let restored = ProjectTabStore(defaults: defaults).layout(for: project)
            #expect(restored.items == [.changes])
            #expect(restored.left == .changes)
            #expect(restored.right == nil)
            #expect(!restored.focusesRight)
        }
    }

    @Test func newChatTabSavedByOlderVersionIsDroppedOnLoad() throws {
        let suite = "phlox.projectTabs.legacyNewChat.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        var layout = ProjectTabLayout()
        layout.open(.changes); layout.open(.newChat)
        var old = ProjectTabsSnapshot()
        old.projects[project] = layout
        defaults.set(try JSONEncoder().encode(old), forKey: ProjectTabStore.defaultsKey)

        let restored = ProjectTabStore(defaults: defaults).layout(for: project)

        #expect(restored.items == [.changes])
        #expect(restored.left == nil, "選択は ensureProjectSelection が選び直す")
    }

    @Test func hiddenTransientTabsLeavePersistentSplitAndFocusIntact() throws {
        let suite = "phlox.projectTabs.split.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        let store = ProjectTabStore(defaults: defaults)
        store.updateLayout(for: project) {
            for tab in [ProjectTab.newChat, .changes, .file("a.txt"), .terminal(TerminalTabID()), .browser, .simulator] { $0.open(tab) }
            $0.left = .changes; $0.right = .file("a.txt"); $0.focusesRight = true; $0.splitFraction = 0.37
        }
        let restored = ProjectTabStore(defaults: defaults).layout(for: project)
        #expect(restored.items == [.changes, .file("a.txt")])
        #expect(restored.left == .changes && restored.right == .file("a.txt"))
        #expect(restored.focusesRight)
        #expect(restored.splitFraction == 0.37)
    }

    @Test func persistenceDropsTransientTabsAndChatSelection() throws {
        let suite = "phlox.projectTabs.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        let store = ProjectTabStore(defaults: defaults)
        store.updateLayout(for: project) {
            for tab in [ProjectTab.newChat, .changes, .file("a.txt"), .terminal(TerminalTabID()), .browser, .simulator] { $0.open(tab) }
            $0.left = .browser
            $0.right = .file("a.txt")
            $0.focusesRight = true
            $0.splitFraction = 0.37
        }
        let restored = ProjectTabStore(defaults: defaults).layout(for: project)
        #expect(restored.items == [.changes, .file("a.txt")])
        #expect(restored.left == .file("a.txt"))
        #expect(restored.right == nil)
        #expect(!restored.focusesRight)
        #expect(restored.splitFraction == 0.37)
        #expect(store.layout(for: project).left == .browser)
        store.updateLayout(for: project) { $0.left = .chat(SessionID()); $0.right = .simulator }
        let saved = ProjectTabStore(defaults: defaults).layout(for: project)
        #expect(saved.left == nil)
        #expect(saved.right == nil)
    }

    @Test func legacyMigrationIsProjectScopedValidatedAndOnceOnly() throws {
        let suite = "phlox.projectTabs.migration.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("a.txt"))
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data().write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.txt"), withDestinationURL: outside)
        let project = Project(id: ProjectID(), name: "project", directoryPath: root.path, createdAt: Date(), isManagedDirectory: false)
        let session = SessionID()
        let legacy = LegacySnapshot(sessions: [session: LegacyLayout(tabs: [.conversation, .terminal, .changes, .file("a.txt"), .file("missing.txt"), .file("../\(outside.lastPathComponent)"), .file("escape.txt")])])
        let data = try JSONEncoder().encode(legacy)
        defaults.set(data, forKey: "phlox.sessionTabs.v1")
        let store = ProjectTabStore(defaults: defaults)
        store.migrateLegacy(sessionProjects: [session: project.id], projects: [project])
        #expect(store.layout(for: project.id).items == [.changes, .file("a.txt")])
        #expect(defaults.data(forKey: "phlox.sessionTabs.v1") == data)
        #expect(defaults.data(forKey: "phlox.projectTabs.v1") != nil)
        store.forgetProject(project.id)
        let again = ProjectTabStore(defaults: defaults)
        again.migrateLegacy(sessionProjects: [session: project.id], projects: [project])
        #expect(again.snapshot.projects.isEmpty)
    }

    @Test func emptyMigrationAlsoWritesNewKey() throws {
        let suite = "phlox.projectTabs.empty.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(LegacySnapshot(sessions: [:])), forKey: "phlox.sessionTabs.v1")
        ProjectTabStore(defaults: defaults).migrateLegacy(sessionProjects: [:], projects: [])
        #expect(defaults.data(forKey: "phlox.projectTabs.v1") != nil)
    }
}

private enum LegacyTab: Codable { case conversation, terminal, changes, file(String) }
private struct LegacyLayout: Codable {
    var tabs: [LegacyTab]
    var left: LegacyTab = .conversation
    var right: LegacyTab?
    var focusesRight = false
    var splitFraction = 0.5
}
private struct LegacySnapshot: Codable { var sessions: [SessionID: LegacyLayout] }
