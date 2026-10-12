import Foundation
import Testing
import AgentDomain
import DesignSystem
@testable import DashboardFeature

@Suite @MainActor struct ProjectTabsPresentationTests {
    @Test func closeRequestsRouteToTheMatchingDeletionConfirmation() {
        let project = ProjectID()
        let session = SessionID()
        let router = AppRouter(selectedSession: session)
        router.selectedProjectID = project
        router.tabs.updateLayout(for: project) { $0.open(.chat(session)) }

        #expect(router.requestClose())
        #expect(router.tabRequest == .confirmSessionDeletion(session))
        #expect(router.requestClose(.session(session)))
        #expect(router.tabRequest == .confirmSessionDeletion(session))
        #expect(router.requestClose(.project(project)))
        #expect(router.tabRequest == .confirmProjectDeletion(project))
    }

    @Test func overflowingRowsShrinkBeforeHidingAndKeepTheSelectionVisible() {
        let single = TabBarOverflowLayout.make(
            itemCount: 1, selectedIndex: 0, availableWidth: 100,
            maxItemWidth: 180, minItemWidth: 96, addButtonWidth: 30, overflowButtonWidth: 70
        )
        #expect(single.visibleIndices == [0])
        #expect(single.itemWidth == 70)
        #expect(single.overflowCount == 0)

        let expanded = TabBarOverflowLayout.make(
            itemCount: 3, selectedIndex: 2, availableWidth: 570,
            maxItemWidth: 180, minItemWidth: 96, addButtonWidth: 30, overflowButtonWidth: 70
        )
        #expect(expanded.visibleIndices == [0, 1, 2])
        #expect(expanded.itemWidth == 180)
        #expect(expanded.overflowCount == 0)

        let shrunk = TabBarOverflowLayout.make(
            itemCount: 4, selectedIndex: 3, availableWidth: 570,
            maxItemWidth: 180, minItemWidth: 96, addButtonWidth: 30, overflowButtonWidth: 70
        )
        #expect(shrunk.visibleIndices == [0, 1, 2, 3])
        #expect(shrunk.itemWidth < 180)
        #expect(shrunk.itemWidth >= 96)

        let overflow = TabBarOverflowLayout.make(
            itemCount: 6, selectedIndex: 5, availableWidth: 570,
            maxItemWidth: 180, minItemWidth: 96, addButtonWidth: 30, overflowButtonWidth: 70
        )
        #expect(overflow.visibleIndices.contains(5))
        #expect(overflow.visibleIndices.count == 4)
        #expect(overflow.overflowCount == 2)
        #expect(overflow.itemWidth >= 96)
    }

    @Test func childTabsUseContentWidthsAndFoldTheTrailingRunIntoOverflow() {
        let fitted = TabBarOverflowLayout.make(
            contentWidths: [80, 120, 60], selectedIndex: 1, availableWidth: 300,
            maxItemWidth: 200, addButtonWidth: 26, overflowButtonWidth: 70
        )
        #expect(fitted.visibleIndices == [0, 1, 2])
        #expect(fitted.width(for: 0) == 80)
        #expect(fitted.width(for: 1) == 120)

        let overflow = TabBarOverflowLayout.make(
            contentWidths: [150, 150, 100, 90, 150], selectedIndex: 0, availableWidth: 450,
            maxItemWidth: 200, addButtonWidth: 26, overflowButtonWidth: 70
        )
        #expect(overflow.visibleIndices == [0, 1])
        #expect(overflow.overflowCount == 3)
        #expect(overflow.width(for: 0) == 150)
        #expect(overflow.width(for: 1) == 150)
    }

    @Test func tabAccessibilityIdentifiersUseTheSpecifiedNames() {
        #expect(TabAccessibilityIdentifier.project(1) == "tabs.project.1")
        #expect(TabAccessibilityIdentifier.projectAdd == "tabs.project.add")
        #expect(TabAccessibilityIdentifier.item(1) == "tabs.item.1")
        #expect(TabAccessibilityIdentifier.itemAdd == "tabs.item.add")
        #expect(TabAccessibilityIdentifier.overflow == "tabs.overflow")
    }

    @Test func projectCyclingWrapsAcrossSidebarOrder() {
        let projects = [ProjectID(), ProjectID(), ProjectID()]
        let router = AppRouter()
        router.selectedProjectID = projects[2]
        router.cycleProject(by: 1, ordered: projects)
        #expect(router.selectedProjectID == projects[0])
        router.cycleProject(by: -1, ordered: projects)
        #expect(router.selectedProjectID == projects[2])
    }

    @Test func toolbarAndGridSourceMatchTheProjectTabContract() throws {
        let toolbar = try packageSource("Sources/DashboardFeature/Dashboard/DashboardToolbar.swift")
        #expect(!toolbar.contains("titleBlock"))
        #expect(!toolbar.contains("worktreeMenu"))
        #expect(!toolbar.contains("WorktreeMenuButton"))
        #expect(DSLayout.toolbarHeight == 38)

        let chrome = try packageSource("Sources/DashboardFeature/Dashboard/WindowChromeConfigurator.swift")
        #expect(chrome.contains(".unifiedCompact"))

        let tabs = try packageSource("Sources/DashboardFeature/Tabs/SessionTabBar.swift")
        #expect(tabs.contains("ForEach(layout.visibleIndices"))
        #expect(tabs.contains("let project = viewModel.projects[index]"))
        #expect(tabs.contains(".accessibilityIdentifier(TabAccessibilityIdentifier.project(index + 1))"))
        let childTabs = try packageSource("Sources/DashboardFeature/Tabs/SessionTabsContainer.swift")
        #expect(childTabs.contains("layout.tabs(chats: chats)"))
        #expect(childTabs.contains(".accessibilityIdentifier(TabAccessibilityIdentifier.item(index + 1))"))
        #expect(childTabs.contains("router.requestClose(.session(id))"))
        #expect(childTabs.contains("worktree で実行中"))
        #expect(childTabs.contains(".frame(width: 440)"))
        #expect(childTabs.contains("[.newChat, .terminal, .changes, .file, .browser, .simulator]"))
        for label in ["新規チャット", "ターミナル", "変更", "ファイルを開く…", "ブラウザ", "シミュレーター",
                      "ターミナル・変更・ファイルは "] {
            #expect(childTabs.contains(label))
        }

        let app = try appSource("App/PhloxApp.swift")
        #expect(app.contains("keyboardShortcut(.tab, modifiers: .control)"))
        #expect(app.contains("keyboardShortcut(.tab, modifiers: [.control, .shift])"))
        #expect(app.contains("keyboardShortcut(\"[\", modifiers: [.command, .shift])"))
        #expect(app.contains("keyboardShortcut(\"]\", modifiers: [.command, .shift])"))
        #expect(app.contains("keyboardShortcut(\"t\", modifiers: .command)"))
        #expect(!app.contains("ターミナルのタブ"))
        #expect(!app.contains("keyboardShortcut(\"t\", modifiers: [.command, .control])"))
    }

    @Test func commonTerminalIsAbsentFromTheRuntimeAndGridTilesHaveNoChildTabs() throws {
        let files = [
            "Sources/DashboardFeature/Router/AppRouter.swift",
            "Sources/DashboardFeature/Dashboard/DashboardView.swift",
            "Sources/DashboardFeature/Files/FileTreeRows.swift",
            "Sources/DashboardFeature/Files/FileTreeView.swift",
            "Sources/DashboardFeature/Tabs/FileTabOpening.swift",
            "Sources/DashboardFeature/Tabs/SessionTabBar.swift",
            "Sources/DashboardFeature/Tabs/SessionTabsContainer.swift",
        ]
        for file in files { #expect(try !packageSource(file).contains("commonTerminal")) }

        let app = try appSource("App/PhloxApp.swift")
        #expect(!app.contains("commonTerminal"))
        for file in [
            "../SessionFeature/Sources/SessionFeature/GridTileParts.swift",
            "../SessionFeature/Sources/SessionFeature/PaneLayoutView.swift",
            "../SessionFeature/Sources/SessionFeature/SessionGridView.swift",
            "Sources/DashboardFeature/Dashboard/DashboardDetailView.swift",
            "Sources/DashboardFeature/Dashboard/DashboardView.swift",
        ] {
            let source = try packageSource(file)
            #expect(!source.contains("GridTileTabs"))
            #expect(!source.contains("tileTabs"))
        }
    }

    private func packageSource(_ path: String) throws -> String {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: package.appendingPathComponent(path), encoding: .utf8)
    }

    private func appSource(_ path: String) throws -> String {
        let macos = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: macos.appendingPathComponent(path), encoding: .utf8)
    }
}
