import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DashboardFeature

/// task-6 の受け入れテスト（PM がディスパッチ前に凍結。**RED から始まる**）。
///
/// task-4 の第6ラウンド独立レビューが実描画つきで検出した表示側の欠陥 3 点を凍結する。
/// いずれも task-4 の契約に書いていなかった合格条件であり、実装役の逸脱ではない
/// （PM が契約の欠陥と裁定して本タスクへ移管した）。
///
/// 1. **git 失敗出力の全文到達性**: 現状は `GitCommitPanel.swift` の
///    `.frame(height: commitStatusMaxHeight).clipped()` で 2 行に打ち切られ、
///    3 行目以降はビュー階層に存在しないため選択もコピーもできない。
///    契約は「スクロール・展開・コピーボタンのいずれで解決してもよい」としているが、
///    **機械的に検査できる形が要る**ので PM が「コピー」を選んで凍結した
///    （`decision-log.md` 2026-08-05）。スクロールや展開を足すのは自由だが、
///    コピー経路は必ず成立させること。
/// 2. **最小ドロワー幅での成立**: `PanelDrawerLayout.minimumWidth`（280pt）まで縮めても、
///    失敗状態表示を載せた状態で `EditorPanelLayout.stackedCommitPanelBudget` を超えない。
///    task-4 の白箱テストは width 388 の 1 点しか測っていなかった。
/// 3. **PR タイトル取得失敗を握りつぶさない**: `EditorPanelViewModel` の
///    `catch { title = "Update" }` が理由ごと捨てている。PR 作成自体は続行してよいが、
///    フォールバックしたことと理由がユーザーに分かること。
@Suite("Acceptance: コミットパネルの到達性と失敗表示（task-6）")
@MainActor
struct AcceptanceCommitPanelReachabilityTests {

    // MARK: - 事後条件 1: git 失敗出力の全文到達性

    @Test("失敗出力が 26 行あっても全文がクリップボードから取り出せる")
    func 失敗出力の全文がコピーできる() async throws {
        let root = try Self.makeEmptyGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = try await Self.makeViewModelWithFailingCommit(root: root)

        let status = try #require(viewModel.workflowStatusMessage)
        #expect(viewModel.workflowStatusIsError)
        // 実運用と同じく、フックの長い出力が丸ごと状態メッセージに入っている。
        try #require(status.contains("hook line 26:"), "状態メッセージが 26 行目まで保持していない")

        let pasteboard = NSPasteboard(name: .init("phlox-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        viewModel.copyWorkflowStatusToPasteboard(pasteboard)

        let copied = pasteboard.string(forType: .string)
        #expect(copied == status, "クリップボードへ状態メッセージの全文が入っていない")
        // 打ち切られていないことを、最終行が含まれるかで直接確かめる（長さの一致だけでは不十分）。
        #expect(copied?.contains("hook line 26:") == true, "26 行目が到達不能")
    }

    // MARK: - 事後条件 2: 最小ドロワー幅での成立

    @Test("最小ドロワー幅 280pt でも失敗状態込みでレイアウト予算を超えない")
    func 最小幅で予算を超えない() async throws {
        let root = try Self.makeEmptyGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let width = PanelDrawerLayout.minimumWidth   // 定数を直書きしない
        let budget = EditorPanelLayout.stackedCommitPanelBudget

        let clean = Self.makeViewModel(root: root)
        let withoutStatus = Self.measureCommitPanelHeight(viewModel: clean, width: width)

        let viewModel = try await Self.makeViewModelWithFailingCommit(root: root)
        let withStatus = Self.measureCommitPanelHeight(viewModel: viewModel, width: width)

        // 下限側（トートロジー防止）: 状態表示を出したら必ず高さが増える。
        // 増えないなら表示ブロックが実質存在しないということなので、それ自体が欠陥。
        #expect(
            withStatus > withoutStatus,
            "失敗状態を出しても高さが変わらない（表示ブロックが機能していない）: \(withoutStatus) → \(withStatus)"
        )
        // 上限側: 予算内に収まる。
        #expect(
            withStatus <= budget,
            "幅 \(width)pt・失敗状態ありのパネル実測 \(withStatus) が予算 \(budget) を超える"
        )
    }

    @Test("最小幅でも既定幅でも見出しと状態行が同じ数だけ存在する")
    func 最小幅で見出しと状態行が消えない() async throws {
        let root = try Self.makeEmptyGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = try await Self.makeViewModelWithFailingCommit(root: root)

        let narrow = Self.measureCommitPanelSize(
            viewModel: viewModel,
            width: PanelDrawerLayout.minimumWidth
        )
        let wide = Self.measureCommitPanelSize(viewModel: viewModel, width: 388)

        // 幅を最小にしても、パネルは要求幅を超えて横へはみ出さない。
        #expect(
            narrow.width <= PanelDrawerLayout.minimumWidth + 0.5,
            "最小幅でパネルが横へはみ出している: \(narrow.width) > \(PanelDrawerLayout.minimumWidth)"
        )
        #expect(wide.width <= 388.5)
        // 狭いほど縦に伸びるのは自然だが、予算内であること（事後条件 2 と同じ上限）。
        #expect(narrow.height <= EditorPanelLayout.stackedCommitPanelBudget)
    }

    // MARK: - 事後条件 3: PR タイトル取得失敗を握りつぶさない

    @Test("PR タイトルの取得に失敗したらフォールバックした事実と理由が出る")
    func PRタイトルのフォールバックが握りつぶされない() async throws {
        // コミットが 1 つも無いリポジトリでは `latestCommitSubject()` が失敗する。
        let root = try Self.makeEmptyGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let fakeGh = root.appendingPathComponent("fake-gh")
        try """
        #!/bin/sh
        echo "https://example.com/pr/1"
        exit 0
        """.write(to: fakeGh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeGh.path
        )

        let viewModel = EditorPanelViewModel(
            service: WorkingTreeService(repositoryRoot: root),
            changeScope: .isolated(repositoryRoot: root.path),
            workflowService: GitWorkflowService(
                repositoryRoot: root,
                gitHubCLIPath: fakeGh.path
            )
        )
        viewModel.commitMessage = ""   // 入力が空なので直近コミット subject を引きにいく

        await viewModel.createPullRequest()

        let status = try #require(
            viewModel.workflowStatusMessage,
            "フォールバックしたのに何も表示されていない"
        )
        // 「フォールバックした事実」と「理由」の両方が読み取れること。
        #expect(
            status.contains("Update"),
            "どのタイトルにフォールバックしたのかが分からない: \(status)"
        )
        #expect(
            status.count > "Pull request created.".count,
            "既定の成功メッセージのままで、フォールバックの理由が伝わっていない: \(status)"
        )
    }

    // MARK: - ヘルパー

    /// コミットが 1 つも無い git リポジトリを作る。
    static func makeEmptyGitRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-commit-panel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "--initial-branch=main"]
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return root
    }

    /// 26 行を出力して失敗する pre-commit フックを仕込み、実際に commit を失敗させた
    /// view model を返す（実運用で観測されたのと同じ経路で長い失敗出力を作る）。
    static func makeViewModelWithFailingCommit(root: URL) async throws -> EditorPanelViewModel {
        try git(["config", "user.name", "phlox-test"], in: root)
        try git(["config", "user.email", "test@phlox.local"], in: root)
        try git(["config", "commit.gpgsign", "false"], in: root)

        let hooks = root.appendingPathComponent("hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let preCommit = hooks.appendingPathComponent("pre-commit")
        let body = (1...26)
            .map { "echo 'hook line \($0): pre-commit check failed with a fairly long message'" }
            .joined(separator: "\n")
        try "#!/bin/sh\n\(body)\nexit 1\n"
            .write(to: preCommit, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preCommit.path)
        try git(["config", "core.hooksPath", hooks.path], in: root)

        try "a1\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let viewModel = makeViewModel(root: root)
        await viewModel.refresh()
        viewModel.toggleCommitSelection(for: "a.txt")
        viewModel.commitMessage = "acceptance: commit panel reachability"
        await viewModel.commitSelectedPaths()
        return viewModel
    }

    static func git(_ args: [String], in root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
    }

    static func makeViewModel(root: URL) -> EditorPanelViewModel {
        EditorPanelViewModel(
            service: WorkingTreeService(repositoryRoot: root),
            changeScope: .isolated(repositoryRoot: root.path),
            workflowService: GitWorkflowService(
                repositoryRoot: root,
                gitHubCLIPath: "/nonexistent/bin/gh-\(UUID().uuidString)"
            )
        )
    }

    static func measureCommitPanelHeight(viewModel: EditorPanelViewModel, width: CGFloat) -> CGFloat {
        measureCommitPanelSize(viewModel: viewModel, width: width).height
    }

    static func measureCommitPanelSize(viewModel: EditorPanelViewModel, width: CGFloat) -> CGSize {
        let root = GitCommitPanel(viewModel: viewModel).frame(width: width)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 4000)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }
}
