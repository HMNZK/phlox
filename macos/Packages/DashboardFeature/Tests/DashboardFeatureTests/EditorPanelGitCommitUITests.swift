// エディタパネルの git コミット UI（EditorPanelViewModel と GitCommitPanel）: 理由表示・PR タイトル・状態メッセージの折りたたみ。

import AppKit
import Foundation
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("EditorPanel git commit UI")
@MainActor
struct EditorPanelGitCommitUITests {
    @Test func リモート未設定とgh不在の理由がVMに出る() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-editor-git-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "--initial-branch=main"]
        process.currentDirectoryURL = root
        try process.run()
        process.waitUntilExit()

        let workflow = GitWorkflowService(
            repositoryRoot: root,
            gitHubCLIPath: "/nonexistent/bin/gh-\(UUID().uuidString)"
        )
        let viewModel = EditorPanelViewModel(
            service: WorkingTreeService(repositoryRoot: root),
            changeScope: .isolated(repositoryRoot: root.path),
            workflowService: workflow
        )
        await viewModel.refresh()

        #expect(viewModel.pushAvailabilityReason != nil)
        #expect(viewModel.pushAvailabilityReason?.contains("リモート") == true)
        #expect(!viewModel.canPush)
        #expect(viewModel.pullRequestAvailabilityReason != nil)
        #expect(viewModel.pullRequestAvailabilityReason?.contains("gh") == true)
        #expect(!viewModel.canCreatePullRequest)
    }

    @Test func ステージ済みのコミットをプッシュした後のPRは直近subjectをタイトルにする() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-editor-pr-title-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func git(_ args: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = root
            var env = ProcessInfo.processInfo.environment
            env["GIT_CONFIG_NOSYSTEM"] = "1"
            process.environment = env
            let out = Pipe()
            process.standardOutput = out
            process.standardError = out
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0)
        }

        try git(["init", "--initial-branch=main"])
        try git(["config", "user.name", "phlox-test"])
        try git(["config", "user.email", "test@phlox.local"])
        try git(["config", "commit.gpgsign", "false"])
        try git(["config", "core.hooksPath", "/dev/null"])
        try "a1\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "a.txt"])
        try git(["commit", "-m", "initial"])
        let remote = root.appendingPathComponent("remote.git")
        try git(["init", "--bare", remote.path])
        try git(["remote", "add", "origin", remote.path])
        try git(["push", "--set-upstream", "origin", "main"])

        let fakeGh = root.appendingPathComponent("fake-gh")
        try """
        #!/bin/sh
        while [ $# -gt 0 ]; do
          if [ "$1" = "--title" ]; then
            shift
            printf '%s' "$1" > "$(dirname "$0")/gh-title.txt"
          else
            shift
          fi
        done
        echo "https://example.com/pr/1"
        """.write(to: fakeGh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGh.path)

        try "a2\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let workflow = GitWorkflowService(repositoryRoot: root, gitHubCLIPath: fakeGh.path)
        let viewModel = EditorPanelViewModel(
            service: WorkingTreeService(repositoryRoot: root),
            changeScope: .isolated(repositoryRoot: root.path),
            workflowService: workflow
        )
        await viewModel.refresh()
        await viewModel.stage(paths: ["a.txt"])
        viewModel.commitMessage = "feat: only-this-title"
        await viewModel.commitStagedChanges()
        #expect(viewModel.commitMessage.isEmpty)
        #expect(viewModel.workflowStatusIsError == false)
        #expect(!viewModel.canCreatePullRequest)
        #expect(viewModel.aheadCount == 1)
        await viewModel.pushCommittedChanges()
        #expect(viewModel.workflowStatusIsError == false)
        #expect(viewModel.aheadCount == 0)
        #expect(!viewModel.canPush)
        #expect(viewModel.pushAvailabilityReason?.contains("コミット") == true)
        #expect(viewModel.canCreatePullRequest)

        await viewModel.createPullRequest()
        let titlePath = root.appendingPathComponent("gh-title.txt")
        let title = try String(contentsOf: titlePath, encoding: .utf8)
        #expect(title == "feat: only-this-title")
        #expect(title != "Update")
        try git(["branch", "--unset-upstream"])
        try git(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"])
        await viewModel.refreshWorkflowCapabilities()
        #expect(viewModel.aheadCount == 0)
        #expect(!viewModel.hasUpstream)
        #expect(viewModel.canPush)

    }

    /// 折りたたまれた状態メッセージは、詳細表示を開くまでコンパクトに保たれる。
    @Test func コミットパネルの折りたたまれた状態メッセージはコンパクトに保たれる() {
        let viewModel = EditorPanelViewModel(service: nil, changeScope: .unavailable)
        let withoutStatus = measureCommitPanelHeight(viewModel: viewModel, width: 388)
        viewModel.presentWorkflowError("git commit failed: hook rejected")
        let withStatus = measureCommitPanelHeight(viewModel: viewModel, width: 388)
        #expect(
            withStatus >= withoutStatus + 40,
            "状態表示ブロックが無い／潰れている: without=\(withoutStatus) with=\(withStatus)"
        )
        #expect(withStatus < withoutStatus + 120, "折りたたまれた状態表示が大きすぎる: \(withStatus)")
    }

    /// 長い git 失敗出力は、展開操作まで要約表示に留めて操作部を押し出さない。
    @Test func 長いgit失敗出力でも折りたたまれた状態表示はコンパクトに保たれる() {
        let viewModel = EditorPanelViewModel(service: nil, changeScope: .unavailable)
        let withoutStatus = measureCommitPanelHeight(viewModel: viewModel, width: 388)
        let longOutput = (1...26).map { "hook: lint failed on file_\($0).swift" }.joined(separator: "\n")
        viewModel.presentWorkflowError("git commit -m x -- a.txt failed:\n\(longOutput)")

        let measured = measureCommitPanelHeight(viewModel: viewModel, width: 388)
        #expect(
            measured >= withoutStatus + 40,
            "長い失敗出力でも状態表示ブロックが無い: without=\(withoutStatus) with=\(measured)"
        )
        // 07 D5 の箱: 余白 7 + 要約の行 20 + 間 6 + 畳んだログ 84 + 余白 7 + 欄の間 7 ≈ 131。全文（26 行）なら 400 を超える。
        #expect(measured < withoutStatus + 140, "長い失敗表示が折りたたまれていない: \(measured)")
        #expect(viewModel.workflowStatusMessage != nil)

        viewModel.dismissWorkflowStatus()
        #expect(viewModel.workflowStatusMessage == nil)
        #expect(viewModel.workflowStatusIsError == false)
    }

    @Test func 要件の260ptと340ptでコミットパネルのアクションが収まる() {
        let viewModel = EditorPanelViewModel(service: nil, changeScope: .unavailable)
        for width in [CGFloat(260), 340] {
            let size = measureCommitPanelSize(viewModel: viewModel, width: width)
            #expect(size.width <= width, "操作部が列幅からはみ出す: \(size)")
            #expect(size.height > 60 && size.height < 220, "固定操作部の高さ: \(size)")
        }
    }

    @Test(arguments: [CGFloat(320), 760]) func 未選択の案内と差分の出どころを表示する(_ width: CGFloat) async throws {
        let parent = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build")
        let fixture = try GitWorkflowRenderFixture(parent: parent)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model()
        await model.refresh()
        try await withAccessibilityHost(EditorPanelView(viewModel: model), width: width) { host in
            let notice = try #require(IntegrationFixAccessibility.find("editor-no-selection", in: host))
            #expect((notice as AnyObject).accessibilityRole() == .staticText)
            #expect((notice as AnyObject).accessibilityValue() as? String == "Git タブで変更を選んでください")
            #expect(IntegrationFixAccessibility.find("git-commit-panel", in: host) == nil)
            #expect(IntegrationFixAccessibility.find("editor-change-list", in: host) == nil)
            #expect(IntegrationFixAccessibility.find("editor-no-selection-help", in: host) != nil)
            #expect(IntegrationFixAccessibility.find("editor-git-shortcut", in: host) != nil)
            let edit = try #require(IntegrationFixAccessibility.find("editor-open-file", in: host))
            #expect(!(edit as AnyObject).isAccessibilityEnabled())
        }
        for (source, label) in [(WorkingTreeSource.worktree, "作業ツリー"), (.staged, "ステージ済み")] {
            await model.select("Sources/Workflow.swift", source: source)
            try await withAccessibilityHost(EditorPanelView(viewModel: model), width: width) { host in
                let origin = try #require(IntegrationFixAccessibility.find("editor-diff-source", in: host))
                #expect((origin as AnyObject).accessibilityRole() == .staticText)
                #expect((origin as AnyObject).accessibilityValue() as? String == label)
                #expect(IntegrationFixAccessibility.find("editor-no-selection", in: host) == nil)
                #expect(IntegrationFixAccessibility.find("editor-open-file", in: host) != nil)
                let folder = try #require(IntegrationFixAccessibility.find("editor-diff-folder", in: host))
                #expect((folder as AnyObject).accessibilityValue() as? String == "Sources")
                #expect(IntegrationFixAccessibility.find("editor-diff-counts", in: host) != nil)
                #expect(IntegrationFixAccessibility.find("editor-change-list", in: host) == nil)
            }
        }
    }

    @Test func 短い差分をスクロール領域の上端から表示する() async throws {
        let parent = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build")
        let fixture = try GitWorkflowRenderFixture(parent: parent)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model()
        await model.refresh()
        for source in [WorkingTreeSource.worktree, .staged] {
            await model.select("Sources/Workflow.swift", source: source)
            try await withAccessibilityHost(EditorPanelView(viewModel: model), width: 760) { host in
                let scroll = try #require(IntegrationFixAccessibility.find("editor-diff-scroll", in: host))
                let first = try #require(IntegrationFixAccessibility.find("editor-code-line-0", in: host))
                let topGap = (scroll as AnyObject).accessibilityFrame().maxY - (first as AnyObject).accessibilityFrame().maxY
                #expect(abs((scroll as AnyObject).accessibilityFrame().height - (host.bounds.height - DSLayout.gitDiffHeaderHeight)) <= DSSpacing.xxs)
                #expect(topGap >= 0 && topGap <= DSSpacing.m, "差分先頭の上端からの距離: \(topGap)")
                #expect((first as AnyObject).accessibilityFrame().height <= DSLayout.gitDiffLineHeight + DSSpacing.xxs)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let y = DSLayout.gitDiffHeaderHeight + DSSpacing.chip + DSLayout.gitDiffLineHeight * 2.5
                let sample = try #require(bitmap.colorAt(x: Int(DSSpacing.xxs * CGFloat(bitmap.pixelsWide) / host.bounds.width),
                    y: Int(y * CGFloat(bitmap.pixelsHigh) / host.bounds.height))?.usingColorSpace(.deviceRGB))
                #expect(sample.redComponent > sample.greenComponent + 0.02,
                    "上端付近の削除行が描かれていない: \(sample)")
            }
        }
    }

    @Test func ホバー時はステージ操作とVoiceOverラベルを表示する() async throws {
        let model = EditorPanelViewModel(service: nil, changeScope: .unavailable)
        let path = "Sources/Workflow.swift"
        let change = WorkingTreeChange(path: path, kind: .modified, isBinary: false)
        model.acceptSnapshot(.init(branch: "feature/git-workflow", changes: [change], lineCounts: [:],
            unstagedChanges: [change], unstagedLineCounts: [path: .init(added: 2, deleted: 1)]))
        let view = GitInspectorView(model: model, workingDirectory: "", openChanges: { _, _, _ in },
            openFile: { _ in }, snapshotHoveredSelection: .init(path: path, source: .worktree))
        try await withAccessibilityHost(view) { host in
            let action = try #require(IntegrationFixAccessibility.find("git-stage-" + path, in: host))
            #expect((action as AnyObject).accessibilityLabel() == "ステージ")
        }
    }

    @Test(arguments: [WorkingTreeSource.worktree, .staged])
    func ステージ処理中に閉じた区画は完了後も見出しに入力先がある(_ source: WorkingTreeSource) async throws {
        let fixture = try GitWorkflowRenderFixture(parent: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model()
        await model.refresh()
        await model.select("Sources/Workflow.swift", source: source)
        var finish: CheckedContinuation<WorkingTreeDetail, Never>?
        model.detailLoader = { _, _ in await withCheckedContinuation { finish = $0 } }
        let view = GitInspectorView(model: model, workingDirectory: fixture.root.path,
            openChanges: { _, _, _ in }, openFile: { _ in },
            snapshotHoveredSelection: .init(path: "Sources/Workflow.swift", source: source))
        try await withAccessibilityHost(view) { host in
            let identifier = source == .staged ? "git-unstage-Sources/Workflow.swift" : "git-stage-Sources/Workflow.swift"
            let stage = try #require(IntegrationFixAccessibility.find(identifier, in: host))
            #expect((stage as AnyObject).accessibilityPerformPress())
            for _ in 0..<200 where finish == nil { try await Task.sleep(for: .milliseconds(10)) }
            let continuation = try #require(finish)
            // 完了後の次行選択がもう一度待機しないよう、取得口を通常へ戻す。
            model.detailLoader = nil
            let header = try #require(IntegrationFixAccessibility.find("git-section-changes-toggle", in: host))
            #expect((header as AnyObject).accessibilityPerformPress())
            try await Task.sleep(for: .milliseconds(100))
            continuation.resume(returning: .diff("待機していた差分"))
            for _ in 0..<200 where model.isWorkflowBusy { try await Task.sleep(for: .milliseconds(10)) }
            #expect(!model.isWorkflowBusy)
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let collapsedHeader = try #require(IntegrationFixAccessibility.find("git-section-changes-toggle", in: host))
            let headerRect = (collapsedHeader as AnyObject).accessibilityFrame()
            // SwiftUIの入力先はNSHostingView内のAX要素。firstResponderの枠はホスト全体になる。
            let selector = NSSelectorFromString("accessibilityFocusedUIElement")
            let focused = try #require(host.perform(selector)?.takeUnretainedValue() as? NSObject)
            let focus = (focused as AnyObject).accessibilityFrame()
            #expect(focus.intersects(headerRect))
            #expect(focus.height <= DSLayout.gitRowHeight + DSSpacing.xxs, "一覧全体ではなく見出しが入力先である")
            #expect((collapsedHeader as AnyObject).accessibilityValue() as? String == "折りたたみ中")
        }
    }

    private func withAccessibilityHost(_ content: some View, width: CGFloat = 340, check: (NSView) async throws -> Void) async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suiteName = "EditorPanelGitCommitUITests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "phlox.inspector.git.changesExpanded"
        defaults.set(true, forKey: key)
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }
        let host = NSHostingView(rootView: content.defaultAppStorage(defaults)
            .environment(\.locale, Locale(identifier: "ja")).frame(width: width, height: 520))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 520),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        try await check(host)
    }

    @MainActor
    private func measureCommitPanelHeight(viewModel: EditorPanelViewModel, width: CGFloat) -> CGFloat {
        measureCommitPanelSize(viewModel: viewModel, width: width).height
    }

    @MainActor
    private func measureCommitPanelSize(
        viewModel: EditorPanelViewModel,
        width: CGFloat
    ) -> CGSize {
        let root = GitCommitPanel(viewModel: viewModel)
            .frame(width: width)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 4000)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }
}
