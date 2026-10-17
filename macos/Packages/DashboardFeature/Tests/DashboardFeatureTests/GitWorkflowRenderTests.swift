import AppKit
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

/// 実アプリを起動せず、Git と「変更」タブの実部品を画面外で描画する。
extension ThemeRenderingTests {
@Suite("Git ワークフローの描画", .serialized) @MainActor
struct GitWorkflowRenderTests {
    @Test func 主要状態の比較画像を書き出す() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PHLOX_DESIGN_SNAPSHOTS"] == "1",
              ["git-workflow", "git-rereview"].contains(environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] ?? "") else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = workspace.appendingPathComponent(".build/git-workflow-snapshots")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = try GitWorkflowRenderFixture(parent: output)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let cachedStrings = output.appendingPathComponent("FileLocalization.bundle")
        if FileManager.default.fileExists(atPath: cachedStrings.path) {
            try FileManager.default.removeItem(at: cachedStrings)
        }
        let strings = try DesignSnapshotRenderTests().localizationBundle(fixtures: output)
        #expect(AppLocalizedString.string("競合", locale: Locale(identifier: "en"), bundle: strings) == "Conflicts")
        #expect(AppLocalizedString.string("競合をターミナルなどで解消してください", locale: Locale(identifier: "en"), bundle: strings)
                == "Resolve conflicts in a terminal or another tool")
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let appearance = NSApp.appearance
        defer {
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            NSApp.appearance = appearance
        }
        var capturedNames: [String] = []
        for light in [false, true] {
            var themed = arguments
            themed[ThemeStore.themeKey] = light ? AppTheme.phloxLight.id : AppTheme.phlox.id
            themed["phlox.inspector.git.changesExpanded"] = true
            defaults.setVolatileDomain(themed, forName: UserDefaults.argumentDomain)
            NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
            for language in ["ja", "en"] {
                for width in [CGFloat(260), 340] {
                    for state in ["normal", "unstaged", "hover", "failure", "conflict"] {
                        let model = fixture.model()
                        await model.refresh()
                        model.commitMessage = language == "en" ? "Gather Git workflow actions" : "Git の操作をまとめる"
                        if state == "unstaged" {
                            let changes = model.unstagedChanges
                            model.acceptSnapshot(.init(branch: "feature/git-workflow", changes: changes,
                                lineCounts: model.unstagedLineCounts, unstagedChanges: changes,
                                unstagedLineCounts: model.unstagedLineCounts))
                        }
                        if state == "conflict" {
                            model.acceptSnapshot(.init(branch: model.branchLabel, changes: model.changes,
                                lineCounts: model.lineCounts, stagedChanges: model.stagedChanges,
                                unstagedChanges: model.unstagedChanges, conflictedPaths: ["Sources/Conflict.swift"],
                                stagedLineCounts: model.stagedLineCounts, unstagedLineCounts: model.unstagedLineCounts))
                        }
                        if state == "failure" {
                            model.presentWorkflowError("git commit が失敗しました:\npre-commit: lint failed\nSources/Workflow.swift:42: error\nコミットは作成されませんでした\n修正してから再実行してください")
                        }
                        let hover: GitChangeSelection? = state == "hover" ? .init(path: "Sources/Workflow.swift", source: .worktree) : nil
                        let view = GitInspectorView(model: model, workingDirectory: fixture.root.path,
                            openChanges: { _, _, _ in }, openFile: { _ in }, snapshotHoveredSelection: hover)
                        let name = "git-\(state)-\(Int(width))-\(light ? "light" : "dark")-\(language)"
                        capturedNames.append(name)
                        try await capture(view, name: name,
                            width: width, height: 620, light: light, language: language, strings: strings, output: output)
                    }
                }
                for source in [WorkingTreeSource.worktree, .staged] {
                    let model = fixture.model()
                    await model.refresh()
                    await model.select("Sources/Workflow.swift", source: source)
                    let name = "changes-\(source.rawValue)-\(light ? "light" : "dark")-\(language)"
                    capturedNames.append(name)
                    try await capture(EditorPanelView(viewModel: model, workingDirectory: fixture.root.path), name: name,
                        width: 760, height: 520, light: light, language: language, strings: strings, output: output)
                }
                let model = fixture.model()
                await model.refresh()
                let name = "changes-unselected-\(light ? "light" : "dark")-\(language)"
                capturedNames.append(name)
                try await capture(EditorPanelView(viewModel: model, workingDirectory: fixture.root.path), name: name,
                    width: 760, height: 520, light: light, language: language, strings: strings, output: output)
            }
        }
        #expect(capturedNames.count == 52)
        #expect(Set(capturedNames).count == 52)
        for name in capturedNames {
            let data = try Data(contentsOf: output.appendingPathComponent(name + ".png"))
            #expect(data.count > 100, "空の比較画像: \(name)")
            #expect(data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
        }
    }

    var workspace: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return root
    }

    func capture(_ content: some View, name: String, width: CGFloat, height: CGFloat,
                         light: Bool, language: String, strings: Bundle, output: URL) async throws {
        let host = NSHostingView(rootView: content
            .environment(\.localizationBundle, strings)
            .environment(\.locale, Locale(identifier: language))
            .environment(\.colorScheme, light ? .light : .dark)
            .frame(width: width, height: height).background(DSColor.background))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: image) }
        let png = try #require(image.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent(name + ".png"))
        #expect(image.pixelsWide > 0 && image.pixelsHigh > 0)
    }
}
}

/// ステージ済みと作業ツリーの差分を同一ファイルに保持する実リポジトリ。
@MainActor
struct GitWorkflowRenderFixture {
    let root: URL

    init(parent: URL) throws {
        root = parent.appendingPathComponent("git-workflow-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try git(["init", "--initial-branch=feature/git-workflow"])
        try git(["config", "user.name", "Phlox Test"])
        try git(["config", "user.email", "test@phlox.local"])
        try write("struct Workflow {\n    let message = \"initial\"\n}\n", path: "Sources/Workflow.swift")
        try git(["add", "--", ":(literal)Sources/Workflow.swift"])
        try git(["-c", "commit.gpgsign=false", "commit", "-m", "初期コミット"])
        try write("struct Workflow {\n    let message = \"staged\"\n}\n", path: "Sources/Workflow.swift")
        try git(["add", "--", ":(literal)Sources/Workflow.swift"])
        try write("struct Workflow {\n    let message = \"worktree\"\n    let enabled = true\n}\n", path: "Sources/Workflow.swift")
        try write("# 作業メモ\n", path: "notes.md")
    }

    func model() -> EditorPanelViewModel {
        EditorPanelViewModel(service: WorkingTreeService(repositoryRoot: root),
            changeScope: .isolated(repositoryRoot: root.path),
            workflowService: GitWorkflowService(repositoryRoot: root, gitHubCLIPath: "/nonexistent/phlox-test-gh"))
    }

    /// 外周の検査位置を、追加・削除の塗りや行番号から離れた中立の行にする。
    func prepareContextDiff() throws {
        let context = (1...100).map { "    // context line \($0)" }.joined(separator: "\n")
        try write("// before\n" + context + "\n", path: "Sources/Workflow.swift")
        try git(["add", "--", ":(literal)Sources/Workflow.swift"])
        try git(["config", "diff.context", "100"])
        try write("// after\n" + context + "\n", path: "Sources/Workflow.swift")
    }

    private func write(_ content: String, path: String) throws {
        try content.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    private func git(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "git \(arguments): \(String(decoding: data, as: UTF8.self))")
    }
}
