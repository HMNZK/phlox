import AppKit
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

extension ThemeRenderingTests {
@Suite("GitHistoryRender", .serialized) @MainActor
struct GitHistoryRenderTests {
    @Test func 各区画と空と開いた履歴と確認と失敗の比較画像() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PHLOX_DESIGN_SNAPSHOTS"] == "1",
              ["git-history", "git-rereview"].contains(environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] ?? "") else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let renderer = GitWorkflowRenderTests()
        let output = renderer.workspace.appendingPathComponent(".build/git-history-snapshots")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cachedStrings = output.appendingPathComponent("FileLocalization.bundle")
        if FileManager.default.fileExists(atPath: cachedStrings.path) {
            try FileManager.default.removeItem(at: cachedStrings)
        }
        let strings = try DesignSnapshotRenderTests().localizationBundle(fixtures: output)
        #expect(AppLocalizedString.string("競合", locale: Locale(identifier: "en"), bundle: strings) == "Conflicts")
        let fixture = try GitHistoryFixture()
        let empty = try GitHistoryFixture(unborn: true)
        defer { fixture.remove(); empty.remove() }
        try fixture.git(["branch", "feature/side"])
        try fixture.git(["tag", "v1.10.0"])
        try fixture.git(["update-ref", "refs/remotes/origin/main", "HEAD"])
        try fixture.git(["update-ref", "refs/remotes/upstream/main", "HEAD"])
        try fixture.git(["config", "branch.main.remote", "origin"])
        try fixture.git(["config", "branch.main.merge", "refs/heads/main"])
        try fixture.git(["config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"])
        try "".write(to: fixture.root.appendingPathComponent(".git/FETCH_HEAD"), atomically: true, encoding: .utf8)
        try fixture.git(["switch", "feature/side"])
        try fixture.write("side branch\n", path: "side.txt")
        try fixture.git(["add", "."])
        try fixture.git(["commit", "-m", "サイドバーの入力先を改善"])
        try fixture.git(["switch", "main"])
        try fixture.write("main branch\n", path: "main.txt")
        try fixture.git(["add", "."])
        try fixture.git(["commit", "-m", "Git の操作をまとめる"])
        try fixture.git(["merge", "--no-ff", "feature/side", "-m", "ブランチを統合"])
        try fixture.write("stash version\n")
        try fixture.write("untracked file\n", path: "notes.md")
        try await fixture.workflow.perform(.stash("作業中の変更"))
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let appearance = NSApp.appearance
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain); NSApp.appearance = appearance }
        var names: [String] = []
        for light in [false, true] {
            for language in ["ja", "en"] {
                var settings = original
                settings[ThemeStore.themeKey] = light ? AppTheme.phloxLight.id : AppTheme.phlox.id
                settings["phlox.inspector.git.changesExpanded"] = false
                for section in GitHistorySection.allCases { settings[section.storageKey] = false }
                defaults.setVolatileDomain(settings, forName: UserDefaults.argumentDomain)
                NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
                for section in GitHistorySection.allCases {
                    settings[section.storageKey] = true
                    defaults.setVolatileDomain(settings, forName: UserDefaults.argumentDomain)
                    for state in ["normal", "empty", "expanded"] {
                        if state == "expanded" && section != .commits && section != .stashes && section != .graph { continue }
                        let model = (state == "empty" ? empty : fixture).model()
                        await model.refresh()
                        await model.setHistorySection(section, expanded: true)
                        if state == "expanded" {
                            if section == .stashes, let stash = model.gitStashes.first { await model.toggleHistoryRow(stash.source) }
                            else if let commit = (section == .graph ? model.graphRows.map(\.commit) : model.historyCommits).first {
                                await model.toggleHistoryRow(.commit(commit.id))
                            }
                        }
                        for width: CGFloat in [260, 340] {
                            let name = "\(section.rawValue)-\(state)-\(Int(width))-\(light ? "light" : "dark")-\(language)"
                            names.append(name)
                            try await renderer.capture(GitInspectorView(model: model, workingDirectory: fixture.root.path,
                                openChanges: { _, _, _ in }, openFile: { _ in }), name: name, width: width, height: 760,
                                light: light, language: language, strings: strings, output: output)
                        }
                    }
                    settings[section.storageKey] = false
                }
                let actions: [GitRepositoryAction] = [.deleteBranch("feature/side", force: false), .deleteBranch("feature/side", force: true),
                    .dropStash("9f3c2e1"), .switchBranch("main"), .stash(""), .popStash("9f3c2e1"), .checkoutRemote("origin/main")]
                for (index, action) in actions.enumerated() {
                    let name = "confirm-\(index)-\(light ? "light" : "dark")-\(language)"
                    names.append(name)
                    try await renderer.capture(GitActionConfirmation(action: action, runningSessions: action.changesWorkingTree ? ["作業中のセッション"] : [],
                        changeCount: 9, untrackedCount: 2,
                        cancel: {}, perform: {}), name: name, width: 340, height: 460, light: light, language: language, strings: strings, output: output)
                }
                let model = fixture.model()
                await model.refresh()
                model.presentWorkflowError("error: Your local changes would be overwritten by checkout:\n  a.txt\nPlease commit your changes or stash them before you switch branches.\nAborting")
                let name = "failure-\(light ? "light" : "dark")-\(language)"
                names.append(name)
                try await renderer.capture(GitInspectorView(model: model, workingDirectory: fixture.root.path, openChanges: { _, _, _ in }, openFile: { _ in }),
                    name: name, width: 340, height: 760, light: light, language: language, strings: strings, output: output)
                for source in [WorkingTreeSource.commit(try #require(try await fixture.reader.history().first).id),
                               try #require(try await fixture.reader.stashes().first).source] {
                    let detail = fixture.model()
                    await detail.refresh()
                    let path = try #require(try await fixture.reader.historyFiles(source: source).first).path
                    await detail.select(path, source: source)
                    let kind = source.rawValue.hasPrefix("stash") ? "stash" : "commit"
                    let name = "changes-\(kind)-\(light ? "light" : "dark")-\(language)"
                    names.append(name)
                    try await renderer.capture(EditorPanelView(viewModel: detail), name: name, width: 760, height: 520,
                        light: light, language: language, strings: strings, output: output)
                }
            }
        }
        #expect(names.count == 144)
        #expect(Set(names).count == names.count)
        for name in names {
            let data = try Data(contentsOf: output.appendingPathComponent(name + ".png"))
            #expect(data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
            #expect(data.count > 100)
        }
    }
}
}
