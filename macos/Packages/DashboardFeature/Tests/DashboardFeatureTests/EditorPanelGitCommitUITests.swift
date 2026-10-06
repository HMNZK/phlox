// エディタパネルの git コミット UI（EditorPanelViewModel と GitCommitPanel）: 理由表示・PR タイトル・状態メッセージの折りたたみ。

import AppKit
import Foundation
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

    @Test func commit成功後のCreatePRは直近コミットsubjectをタイトルにする() async throws {
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
        viewModel.toggleCommitSelection(for: "a.txt")
        viewModel.commitMessage = "feat: only-this-title"
        await viewModel.commitSelectedPaths()
        #expect(viewModel.commitMessage.isEmpty)
        #expect(viewModel.workflowStatusIsError == false)
        #expect(viewModel.canCreatePullRequest)

        await viewModel.createPullRequest()
        let titlePath = root.appendingPathComponent("gh-title.txt")
        let title = try String(contentsOf: titlePath, encoding: .utf8)
        #expect(title == "feat: only-this-title")
        #expect(title != "Update")
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

    /// 狭い split 列幅では ViewThatFits が縦積みへ落ち、高さが広幅より有意に増える。
    @Test func 狭い列幅でもコミットパネルのアクションは収まる() {
        let viewModel = EditorPanelViewModel(service: nil, changeScope: .unavailable)
        let narrow = measureCommitPanelSize(viewModel: viewModel, width: 180)
        let wide = measureCommitPanelSize(viewModel: viewModel, width: 388)
        #expect(
            narrow.height > wide.height + 30,
            "狭い列で ViewThatFits が縦積みへ落ちていない: narrow=\(narrow.height) wide=\(wide.height)"
        )
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
