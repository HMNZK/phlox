import AppKit
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite(.serialized) @MainActor
struct GitDisplayRegressionTests {
    @Test func 同じコミットを両区画で展開してもグラフの行とファイルを区別する() async throws {
        _ = NSApplication.shared
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var settings = original
        settings["phlox.inspector.git.changesExpanded"] = true
        for section in GitHistorySection.allCases { settings[section.storageKey] = true }
        defaults.setVolatileDomain(settings, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        let model = EditorPanelViewModel(service: nil)
        model.acceptSnapshot(.init(branch: "main", changes: [], lineCounts: [:]))
        let commit = GitHistoryCommit(id: "abcdef123456", parents: ["parent"], summary: "共通コミット", author: "Tester",
                                      date: Date(), refs: ["HEAD -> main", "tag: v1"])
        model.historyCommits = [commit]
        model.graphRows = GitGraphRow.make([commit])
        model.localBranches = [.init(name: "main", current: true)]
        model.loadedHistorySections = Set(GitHistorySection.allCases)
        let source = WorkingTreeSource.commit(commit.id)
        model.historyFiles[source] = [.init(path: "a.txt", kind: .modified, isBinary: false)]
        let host = NSHostingView(rootView: GitInspectorView(model: model, workingDirectory: "", openChanges: { _, _, _ in }, openFile: { _ in })
            .environment(\.colorScheme, .dark).frame(width: 340, height: 1500))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 340, height: 1500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 1500)
        window.orderBack(nil)
        defer { window.contentView = nil; window.close() }
        for expanded in [false, true, false, true] {
            model.expandedHistoryRows = expanded ? [source] : []
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let elements = descendants(host)
            let ids = elements.compactMap { value($0, "accessibilityIdentifier") }
            #expect(ids.filter { $0 == "git-commit-\(commit.id)" }.count == 1)
            #expect(ids.filter { $0 == "git-graph-\(commit.id)" }.count == 1)
            let historyIDs = ids.filter { $0.hasPrefix("git-commit-\(commit.id)") || $0.hasPrefix("git-graph-\(commit.id)")
                || $0.hasPrefix("git-history-file-") || $0.hasPrefix("git-graph-file-") }
            #expect(Set(historyIDs).count == historyIDs.count, "履歴行のAX識別子が区画間で重複しない: \(historyIDs)")
            if expanded {
                let file = try #require(IntegrationFixAccessibility.find("git-history-file-\(source.rawValue)-a.txt", in: host))
                let graphFile = try #require(IntegrationFixAccessibility.find("git-graph-file-\(source.rawValue)-a.txt", in: host))
                #expect((graphFile as AnyObject).accessibilityFrame().minX > (file as AnyObject).accessibilityFrame().minX,
                        "グラフのファイルは線の右側に配置する")
            }
            let graph = try #require(IntegrationFixAccessibility.find("git-graph-\(commit.id)", in: host))
            let label = ((graph as AnyObject).accessibilityLabel() ?? "")
                + ((graph as AnyObject).accessibilityValue() as? String ?? "")
            #expect(label.contains("main") && label.contains("v1"), "グラフの札: \(label)")
            // グラフの札と線の分だけ、通常コミットより高さがある。
            let ordinary = try #require(IntegrationFixAccessibility.find("git-commit-\(commit.id)", in: host))
            #expect((graph as AnyObject).accessibilityFrame().height > (ordinary as AnyObject).accessibilityFrame().height)
            let header = try #require(IntegrationFixAccessibility.find("git-section-graph-toggle", in: host))
            #expect(abs((header as AnyObject).accessibilityFrame().minY - (graph as AnyObject).accessibilityFrame().maxY) < DSSpacing.s,
                    "グラフの先頭に余分な行の空白がない")
        }
        try IntegrationFixImage.write(host, name: "git-display-all-sections-expanded")
    }

    @Test func 現在ブランチの先行数は0件なら描かず1件なら矢印と1を描く() async throws {
        _ = NSApplication.shared
        let fixture = try GitHistoryFixture(unborn: true)
        defer { fixture.remove() }
        let model = fixture.model()
        model.acceptSnapshot(.init(branch: "main", changes: [], lineCounts: [:]))
        let view = GitInspectorView(model: model, workingDirectory: fixture.root.path,
                                    openChanges: { _, _, _ in }, openFile: { _ in })
        let blank = try trailingPixels(Spacer(minLength: 0))
        let one = try trailingPixels(HStack(spacing: DSSpacing.chip) {
            Spacer(minLength: 0)
            Text(verbatim: "↑1").font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
        }.padding(.horizontal, DSSpacing.m))
        #expect(!one.elementsEqual(blank), "参照描画に↑1の画素が存在する")

        for count in [0, 1] {
            if count == 1 {
                try fixture.write("initial\n")
                try fixture.git(["add", "a.txt"])
                try fixture.git(["commit", "-m", "initial"])
            }
            await model.refreshWorkflowCapabilities()
            #expect(model.aheadCount == count)
            let actual = try trailingPixels(view.branchRow(.init(name: "main", current: true), remote: false))
            let matchesExpectedPixels = actual.elementsEqual(count == 0 ? blank : one)
            #expect(matchesExpectedPixels,
                    "先行\(count)件のブランチ行右端は\(count == 0 ? "文字なし" : "↑1")の描画と一致する")
        }
    }

    private func trailingPixels(_ content: some View) throws -> [NSColor] {
        let renderer = ImageRenderer(content: content
            .frame(width: 340, height: DSLayout.gitRowHeight)
            .background(DSColor.background).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        // ブランチ名と印を除き、先行数を表示する右端48ptだけを比較する。
        return try (0..<image.pixelsHigh).flatMap { y in
            try ((image.pixelsWide - 96)..<image.pixelsWide).map { x in
                try #require(image.colorAt(x: x, y: y))
            }
        }
    }

    private func value(_ object: NSObject, _ name: String) -> String? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? String
    }

    private func descendants(_ root: NSObject) -> [NSObject] {
        var visited = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) -> [NSObject] {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
            let selector = NSSelectorFromString("accessibilityChildren")
            let children = object.responds(to: selector)
                ? object.perform(selector)?.takeUnretainedValue() as? [NSObject] ?? [] : []
            return [object] + (children + ((object as? NSView)?.subviews ?? [])).flatMap(visit)
        }
        return visit(root)
    }
}
