import AppKit
import AgentDomain
import DesignSystem
import IOSurface
import SimulatorBridgeKit
import SessionFeature
import SwiftUI
import TerminalUI
import Testing
import WebKit
@testable import DashboardFeature

/// 実画面を表示せず、比較用の部品画像を明示指定時だけ書き出す。
@Suite @MainActor
struct DesignSnapshotRenderTests {
    private struct Frame {
        let id: String
        let name: String
        let width: CGFloat
        let height: CGFloat
        var light = false
    }

    private let frames: [Frame] = [
        .init(id: "1a", name: "配置1600", width: 1600, height: 1000),
        .init(id: "1b", name: "配置1000", width: 1000, height: 700),
        .init(id: "1e", name: "配置1200", width: 1200, height: 800),
        .init(id: "1c", name: "サイドバーなし", width: 1200, height: 800),
        .init(id: "1d", name: "タブ追加メニュー", width: 1200, height: 800),
        .init(id: "2a", name: "展開と選択", width: 300, height: 860),
        .init(id: "2b", name: "キーボード移動", width: 300, height: 860),
        .init(id: "2c", name: "右クリック", width: 300, height: 860),
        .init(id: "2d", name: "ルート外ホバー", width: 300, height: 860),
        .init(id: "2e1", name: "ブランチ", width: 300, height: 100),
        .init(id: "2e2", name: "detachedHEAD", width: 300, height: 100),
        .init(id: "2e3", name: "Git管理外", width: 300, height: 100),
        .init(id: "2e4", name: "ブランチ取得失敗", width: 300, height: 100),
        .init(id: "2f", name: "5000件超", width: 300, height: 620),
        .init(id: "2g", name: "読込中", width: 300, height: 620),
        .init(id: "2h", name: "フォルダ読込エラー", width: 300, height: 620),
        .init(id: "2i", name: "セッション未選択", width: 300, height: 620),
        .init(id: "2j", name: "ルート読込エラー", width: 300, height: 620),
        .init(id: "2k", name: "重ね表示", width: 760, height: 720),
        .init(id: "3a", name: "Markdown保存済み", width: 720, height: 300),
        .init(id: "3b", name: "Markdown未保存", width: 720, height: 300),
        .init(id: "3c", name: "Markdownソース", width: 720, height: 300),
        .init(id: "3d", name: "HTML表示", width: 720, height: 300),
        .init(id: "3e", name: "Swiftソース", width: 720, height: 300),
        .init(id: "3f", name: "2000ブロック超", width: 720, height: 300),
        .init(id: "3g", name: "500KB超", width: 720, height: 300),
        .init(id: "3h", name: "ブロック確定失敗", width: 720, height: 300),
        .init(id: "3i", name: "幅480", width: 480, height: 420),
        .init(id: "3j", name: "幅320", width: 320, height: 420),
        .init(id: "3k", name: "幅320英語", width: 320, height: 420),
        .init(id: "3l", name: "1MB超", width: 720, height: 380),
        .init(id: "3m", name: "バイナリ", width: 720, height: 380),
        .init(id: "3n", name: "ルート外", width: 720, height: 380),
        .init(id: "3o", name: "UTF8以外", width: 720, height: 380),
        .init(id: "4a", name: "表示とホバー", width: 760, height: 720),
        .init(id: "4b", name: "段落編集中", width: 760, height: 720),
        .init(id: "4c", name: "frontmatter編集中", width: 760, height: 720),
        .init(id: "4d", name: "長い表編集中", width: 760, height: 720),
        .init(id: "4e", name: "原文", width: 760, height: 340),
        .init(id: "4f", name: "空文書", width: 760, height: 340),
        .init(id: "4g", name: "確定失敗", width: 760, height: 420),
        .init(id: "4h", name: "キーボード選択", width: 760, height: 720),
        .init(id: "4i", name: "リンクホバー", width: 760, height: 720),
        .init(id: "4j", name: "面と輪", width: 560, height: 300),
        .init(id: "4k", name: "面だけ", width: 560, height: 300),
        .init(id: "4l", name: "前後を薄くする", width: 560, height: 300),
        .init(id: "4m", name: "ブロック間選択", width: 560, height: 300),
        .init(id: "5a", name: "HTML通常", width: 760, height: 540),
        .init(id: "5b", name: "遮断説明", width: 760, height: 540),
        .init(id: "5c", name: "ファイルリンク", width: 760, height: 540),
        .init(id: "5d", name: "ブラウザリンク", width: 760, height: 540),
        .init(id: "5e", name: "未保存HTML", width: 760, height: 540),
        .init(id: "5f", name: "表示プロセス終了", width: 760, height: 540),
        .init(id: "5g", name: "遮断準備失敗", width: 760, height: 540),
        .init(id: "5h", name: "HTML幅480", width: 480, height: 540),
        .init(id: "6a", name: "未保存2件", width: 300, height: 340),
        .init(id: "6b", name: "未保存9件", width: 300, height: 440),
        .init(id: "6c", name: "未確定ブロック", width: 300, height: 400),
        .init(id: "6d", name: "2ウィンドウ", width: 300, height: 420),
        .init(id: "6e", name: "3ウィンドウ11件", width: 300, height: 460),
        .init(id: "7r", name: "ショートカット直後", width: 520, height: 760),
        .init(id: "7a", name: "表示中", width: 520, height: 760),
        .init(id: "7b", name: "入力送信中", width: 520, height: 760),
        .init(id: "7c", name: "タップ中", width: 520, height: 760),
        .init(id: "7c2", name: "スクロール中", width: 520, height: 760),
        .init(id: "7d", name: "端末メニュー", width: 520, height: 760),
        .init(id: "7e", name: "停止確認", width: 520, height: 760),
        .init(id: "7f", name: "停止中", width: 520, height: 760),
        .init(id: "7g", name: "起動中", width: 520, height: 760),
        .init(id: "7h", name: "表示のみ", width: 520, height: 760),
        .init(id: "7i", name: "更新なし診断", width: 520, height: 760),
        .init(id: "7j", name: "未確認", width: 520, height: 760),
        .init(id: "7j2", name: "未確認でも試す", width: 520, height: 760),
        .init(id: "7k", name: "Xcodeなし", width: 520, height: 760),
        .init(id: "7l", name: "接続失敗", width: 520, height: 760),
        .init(id: "7m", name: "再起動必要", width: 520, height: 760),
        .init(id: "7n", name: "狭幅の帯", width: 320, height: 700),
        .init(id: "7nStopped", name: "停止中幅320", width: 320, height: 700),
        .init(id: "7TrialInput520", name: "未確認入力中幅520", width: 520, height: 760),
        .init(id: "7StaleInput520", name: "更新なし入力中幅520", width: 520, height: 760),
        .init(id: "7LongStopped320", name: "長い端末名停止中幅320", width: 320, height: 700),
        .init(id: "7LongInput320", name: "長い端末名入力中幅320", width: 320, height: 700),
        .init(id: "7LongTrialStale320", name: "長い端末名未確認更新なし入力中幅320", width: 320, height: 700),
        .init(id: "7ListingError", name: "端末一覧取得失敗", width: 520, height: 760),
        .init(id: "7o", name: "広幅の帯", width: 700, height: 760),
        .init(id: "7p", name: "ベゼルなし", width: 520, height: 640),
        .init(id: "8L1", name: "ライトツリー", width: 300, height: 560, light: true),
        .init(id: "8L2", name: "ライトMarkdown", width: 560, height: 420, light: true),
        .init(id: "8L3", name: "ライト入力送信", width: 520, height: 520, light: true),
    ]

    private struct Unavailable: Error { let reason: String }

    @Test func 比較用画像を書き出す() async throws {
        guard ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }
        _ = NSApplication.shared
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = package.appendingPathComponent(".build/design-snapshot-fixtures-\(UUID().uuidString)")
        let output = URL(fileURLWithPath: "/tmp/phlox-design-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: fixtures) }
            catch { Issue.record("撮影用データを削除できません: \(error)") }
        }
        var rows = ["| 状態 id | 結果 | 補足 |", "|---|---|---|"]
        var written = 0
        var failures: [String] = []
        for frame in frames where ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] != "simulator"
            || frame.id.hasPrefix("7") || frame.id == "8L3" {
            do {
                let existing = destination(frame, output)
                if FileManager.default.fileExists(atPath: existing.path) { try FileManager.default.removeItem(at: existing) }
                let note = try await render(frame, fixtures: fixtures, output: output)
                written += 1
                rows.append("| \(frame.id) | 書き出した | \(note) |")
            } catch let error as Unavailable {
                rows.append("| \(frame.id) | 書き出せない | \(error.reason) |")
            } catch {
                failures.append("\(frame.id): \(error)")
                rows.append("| \(frame.id) | 書き出せない | 描画失敗: \(error) |")
            }
        }
        let report = "# 画面外描画の結果\n\n生成 PNG: \(written) 枚。倍率 2。8L1〜8L3 はライト、ほかはダーク。\n\n"
            + rows.joined(separator: "\n") + "\n"
        try Data(report.utf8).write(to: output.appendingPathComponent("結果.md"), options: .atomic)
        print(report)
        #expect(failures.isEmpty, "予期しない描画失敗: \(failures.joined(separator: "; "))")
        #expect(written > 0)
        if ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOT_SCOPE"] == "simulator" {
            #expect(written == frames.filter { $0.id.hasPrefix("7") || $0.id == "8L3" }.count)
        }
    }

    private func render(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        // ThemeStore は環境の colorScheme ではなく標準設定を読む。永続設定には書き込まない。
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var themeArguments = arguments
        themeArguments[ThemeStore.themeKey] = frame.light ? AppTheme.phloxLight.id : AppTheme.phlox.id
        defaults.setVolatileDomain(themeArguments, forName: UserDefaults.argumentDomain)
        let appearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: frame.light ? .aqua : .darkAqua)
        defer {
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            NSApp.appearance = appearance
        }
        let id = frame.id
        if id == "1d" { throw Unavailable(reason: "タブ追加メニューは非公開状態で、画面外の部品描画に含まれない") }
        if id.hasPrefix("1") { return try await renderDashboard(frame, fixtures: fixtures, output: output) }
        if id.hasPrefix("6") {
            throw Unavailable(reason: "本物の NSAlert を非表示で cacheDisplay すると文字・キャンセルボタン・背景が欠ける。シートを画面に出す方法は今回の制約外")
        }
        let reasons = [
            "2b": "移動中の選択とフォーカスは非公開のビュー状態",
            "2c": "ネイティブの右クリックメニューは画面外の部品描画に含まれない",
            "2d": "ホバーの説明は非公開のポインタ状態",
            "2e2": "ブランチは実 Git から取得し、detached HEAD の注入口がない。撮影用コミットは作らない",
            "2k": "重ね表示のカードはダッシュボードのインスペクタ配置が必要",
            "3h": "文書の版ずれは private(set) で、確定失敗を注入する入口がない",
            "4g": "文書の版ずれを注入する入口がない",
            "4h": "選択ブロックとキーボードフォーカスは非公開のビュー状態",
            "4i": "リンクのホバーは非公開のポインタ状態",
            "4k": "未採用の比較案で切替実装がない",
            "4l": "未採用の比較案で切替実装がない",
            "4m": "選択境界の案内はドラッグ中の非公開状態",
            "5b": "遮断説明ポップオーバーは非公開のビュー状態",
            "5c": "リンクのホバーは FileTabView 内の非公開モデル状態",
            "5d": "リンクのホバーは FileTabView 内の非公開モデル状態",
            "5f": "Web プロセス終了状態は FileTabView 内の非公開モデル。実プロセスは終了させない",
            "5g": "遮断ルール準備失敗を FileTabView に注入する入口がない",
        ]
        if let reason = reasons[id] { throw Unavailable(reason: reason) }
        if id.hasPrefix("2") || id == "8L1" {
            return try await renderTree(frame, fixtures: fixtures, output: output)
        }
        if id.hasPrefix("7") || id == "8L3" {
            return try await renderSimulator(frame, output: output)
        }
        let sessionID = SessionID()
        let files = FileTabDocuments()
        let document = try await makeDocument(frame, fixtures: fixtures, files: files, sessionID: sessionID)
        defer { document.invalidate() }
        let (events, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        defer { continuation.finish() }
        let node = SessionNode.pty(SessionViewModel(id: sessionID, ptyManager: MockPTYManager(),
            hookEvents: events, terminalCoordinator: TerminalCoordinator(),
            spawnRequest: .init(command: "/bin/sh", args: [], env: [:], workingDirectory: document.root,
                                kind: .claudeCode, statusBootstrap: .viaHook)))
        var layout = SessionTabLayout()
        layout.open(.terminal)
        layout.open(.file(document.path))
        let body = FileTabView(document: document, lastWriter: { _ in nil }, isFocused: false, openFile: { _, _ in })
            .environment(\.locale, Locale(identifier: id == "3k" ? "en" : "ja"))
        if id == "4j" {
            try await capture(MarkdownBlockEditor(document: document, openURL: { _ in .discarded }), frame: frame, output: output)
        } else {
            try await capture(VStack(spacing: 0) {
                if id != "8L2" {
                    ChildTabBar(router: AppRouter(), node: node, layout: layout, changeCount: 0,
                                files: files, agentConsoleWindowID: nil)
                }
                body
            }, frame: frame, output: output)
        }
        return id == "3k" ? "英語 locale を指定。現在の実装には日本語文言が残る"
            : ["4a", "4f"].contains(id) ? "本物の本文。見本のホバーの面は対象外（非公開状態）"
            : "実物の子タブ列・ファイル帯・本文。文言・配色は現在の実装値"
    }

    private let markdown = """
    ---
    title: Phlox
    status: draft
    ---

    # Phlox

    Phlox は Claude Code・Codex・Cursor のセッションを並べて走らせ、
    承認待ちと質問だけを前に出す macOS アプリです。詳しくは[設計書][design]を参照してください。

    ## 必要なもの

    - macOS 14 以降
    - Xcode と Claude Code・Codex・Cursor

    ```sh
    cd macos
    swift test
    ```

    | 機能 | 説明 |
    | --- | --- |
    | ファイルツリー | 作業ディレクトリのファイル |
    | Markdown | ブロックごとに編集 |

    [design]: docs/architecture/overview.md
    """

    private func renderDashboard(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        let root = fixtures.appendingPathComponent(frame.id)
        let path = "docs/guides/file-tree.md"
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(markdown.utf8).write(to: file)
        // 作業ディレクトリをこの撮影用ルートに固定する。空の Git リポジトリだけを作り、コミットしない。
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", root.path, "init", "-q", "--initial-branch=main"]
        try git.run()
        git.waitUntilExit()
        try #require(git.terminationStatus == 0)
        let project = Project(name: "phlox-oss", directoryPath: root.path,
                              createdAt: Date(timeIntervalSince1970: 1_000), isManagedDirectory: false)
        let projects = InMemoryProjectStore()
        try await projects.save([project])
        let sessionID = SessionID()
        let (events, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        defer { continuation.finish() }
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: events, projects: projects,
            sessions: InMemorySessionStore([makePersistedSessionDescriptor(id: sessionID, workingDirectory: root.path,
                name: "ファイルツリーをインスペクタに追加", projectID: project.id, startedAt: Date(timeIntervalSince1970: 2_000))]),
            workspaceDirectory: root, agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"]))
        await dashboard.start()
        try #require(dashboard.sessionNodes.contains { $0.id == sessionID })
        let router = AppRouter(viewMode: .single, sidebarVisible: frame.id != "1c", inspectorVisible: true)
        router.selectedSession = sessionID
        router.inspectorTab = .files
        router.tabs.updateLayout(for: sessionID) {
            $0.open(.file(path))
            $0.open(.simulator)
            $0.select(.file(path))
            $0.splitRight(.simulator)
            $0.focusesRight = false
        }
        let fixture = HubCatalogFixture(states: ["iPhone 17": "Shutdown"])
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) { SimulatorDisplayConnection { fake } }
        await hub.refresh()
        defer { hub.disconnectAll() }
        do {
            try await capture(DashboardView(viewModel: dashboard, router: router,
                usageMonitor: UsageMonitor(providers: [:]), simulatorHub: hub), frame: frame, output: output)
        } catch {
            for session in dashboard.sessions { await session.kill() }
            throw error
        }
        for session in dashboard.sessions { await session.kill() }
        #expect(await fixture.mutations().isEmpty)
        return "本物のダッシュボード全体。端末は停止状態の偽物。セッションは1件、タイトルバー・実端末映像は対象外。狭幅の縮退は現在の実装に従う"
    }

    private let html = """
    <!doctype html><html lang="ja"><head><meta charset="utf-8"><style>
    body{margin:0;padding:28px;background:#fff;color:#222;font:14px -apple-system,BlinkMacSystemFont,sans-serif}
    nav{display:flex;gap:24px;border-bottom:1px solid #ddd;padding-bottom:16px}a{color:#a54e2e}
    h1{font-size:32px}p{max-width:520px;line-height:1.7}article{padding:16px;background:#f7f7f8;border-radius:8px}
    </style></head><body><nav><b>Phlox</b><a href="../guides/file-tree.md">ドキュメント</a>
    <a href="releases.html">リリースノート</a><a href="https://github.com/phlox-oss/phlox">GitHub</a></nav>
    <h1>並べて走らせ、判断だけを前に。</h1><p>Phlox は Claude Code・Codex・Cursor のセッションを並べて走らせ、承認待ちと質問だけを前に出します。</p>
    <article><h2>ファイルツリー</h2><p>右サイドバーで作業ツリーを開き、Markdown と HTML を表示します。</p></article></body></html>
    """

    private func makeDocument(_ frame: Frame, fixtures: URL, files: FileTabDocuments, sessionID: SessionID) async throws -> FileTabDocument {
        let id = frame.id
        var path = "docs/guides/file-tree.md"
        var bytes = Data(markdown.utf8)
        if id.hasPrefix("3"), !["3d", "3e", "3f", "3g", "3l", "3m", "3n", "3o"].contains(id) {
            bytes = Data("# ファイルツリー\n\n右サイドバーの「ファイル」タブに、選択中セッションの作業ツリーを表示します。\n\n## 操作\n\n- クリックで開く。開いているタブがあれば前に出す\n- 右クリックで「右に分割して開く」「Finder で表示」「パスをコピー」\n- `⌃⌘B` でツリーを表示\n".utf8)
        }
        if ["3i", "3j", "3k"].contains(id) { path = "macos/Packages/DashboardFeature/docs/guides/file-tree.md" }
        if ["4j", "8L2"].contains(id) {
            bytes = Data(markdown.replacingOccurrences(of: "---\ntitle: Phlox\nstatus: draft\n---\n\n", with: "").utf8)
            path = "README.md"
        }
        switch id {
        case "3d", "5a", "5e", "5h": path = "docs/site/index.html"; bytes = Data(html.utf8)
        case "3e":
            path = "macos/Packages/DashboardFeature/Sources/DashboardFeature/Files/FileTreeRows.swift"
            bytes = Data("import Foundation\n\nenum FileTreeRows {\n    static func visibleRows() {}\n}\n".utf8)
        case "3f":
            path = "docs/changelog/CHANGELOG.md"
            bytes = Data(("# 変更履歴\n\n" + (1...2430).map { "## 変更 \($0)\n\n" }.joined()).utf8)
        case "3g": path = "fixtures/transcripts/long-session.md"; bytes = Data(String(repeating: "変更履歴\n", count: 60_000).utf8)
        case "3l": path = "data/huge-log.txt"; bytes = Data(repeating: 65, count: 1_100_000)
        case "3m": path = "assets/logo.png"; bytes = Data([137, 80, 78, 71, 0])
        case "3o": path = "legacy/README_sjis.txt"; bytes = Data([0x82, 0xa0, 0x82, 0xa2])
        case "4e": path = "docs/links.md"; bytes = Data("[design]: docs/architecture/overview.md\n[adr-0090]: docs/adr/0090-inspector.md\n[simulator]: docs/specs/embedded-ios-simulator.md\n".utf8)
        case "4f": path = "docs/NOTES.md"; bytes = Data()
        case "4d":
            bytes = Data(("| 機能 | 説明 |\n| --- | --- |\n" + (1...20).map { "| 機能\($0) | 長い表の説明 |\n" }.joined()).utf8)
        default: break
        }
        let root = fixtures.appendingPathComponent(id)
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if id == "3n" {
            let outside = fixtures.appendingPathComponent("style-guide.md")
            try bytes.write(to: outside)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        } else { try bytes.write(to: file) }
        let document = files.document(for: sessionID, path: path, root: root.path)
        await document.loadIfNeeded()
        switch id {
        case "3l": try #require(document.loadState == .tooLarge)
        case "3m": try #require(document.loadState == .binary)
        case "3n":
            guard case .outsideRoot = document.loadState else { throw Unavailable(reason: "ルート外のリンク拒否を再現できなかった") }
        case "3o": try #require(document.loadState == .loadFailed)
        default: try #require(document.isLoaded)
        }
        if id == "3f" || id == "3g" { try #require(document.markdownPresentationLocked) }
        if ["3b", "3c", "3i", "3j", "3k"].contains(id) { document.draft += "\n編集した内容。\n" }
        if id == "3c" { document.presentation = .source }
        if id == "5e" {
            document.draft = html.replacingOccurrences(of: "並べて走らせ、判断だけを前に。", with: "未保存の下書きを表示しています。")
            document.reloadHTMLPreview()
        }
        if ["4b", "4c", "4d", "4j", "8L2"].contains(id) {
            let blocks = document.markdownBlocks
            let block = try #require(id == "4c" || id == "4d" ? blocks.first : blocks.first { $0.original.contains("Phlox は") })
            #expect(document.beginBlockEdit(range: block.range))
            if ["4b", "4j", "8L2"].contains(id) {
                let edit = try #require(document.activeBlockEdit)
                document.updateActiveBlockEdit(id: edit.id, current: edit.current + "\n編集中の内容です。")
            }
        }
        return document
    }

    private func renderTree(_ frame: Frame, fixtures: URL, output: URL) async throws -> String {
        let id = frame.id
        let previousCeiling = ProcessInfo.processInfo.environment["GIT_CEILING_DIRECTORIES"]
        if id == "2e3" { setenv("GIT_CEILING_DIRECTORIES", fixtures.path, 1) }
        defer {
            if id == "2e3" {
                if let previousCeiling { setenv("GIT_CEILING_DIRECTORIES", previousCeiling, 1) }
                else { unsetenv("GIT_CEILING_DIRECTORIES") }
            }
        }
        let root = id == "2e1" ? fixtures.deletingLastPathComponent().deletingLastPathComponent().path
            : fixtures.appendingPathComponent(id).path
        if id != "2e4" { try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true) }
        let loader = FileTreeLoader(root: root) { _, path in
            if id == "2j" || (id == "2h" && path == "docs") { throw CocoaError(.fileReadNoPermission) }
            if id == "2g", path == "docs" { try await Task.sleep(for: .seconds(30)) }
            if path == "" {
                return .init(entries: [
                    .init(relativePath: "docs", name: "docs", kind: .directory),
                    .init(relativePath: "macos", name: "macos", kind: .directory),
                    .init(relativePath: "README.md", name: "README.md", kind: .file),
                    .init(relativePath: "CLAUDE.md", name: "CLAUDE.md", kind: .symlinkToFile, resolvedPath: root + "/README.md"),
                    .init(relativePath: "latest", name: "latest", kind: .symlinkToDirectory, resolvedPath: root + "/docs"),
                    .init(relativePath: "shared-assets", name: "shared-assets", kind: .symlinkOutsideRoot,
                          resolvedPath: "/Users/ryosuke/Projects/phlox-shared/assets"),
                ], omittedCount: 0)
            }
            return .init(entries: [
                .init(relativePath: "docs/file-tree.md", name: "file-tree.md", kind: .file),
                .init(relativePath: "docs/step-2.md", name: "step-2.md", kind: .file),
                .init(relativePath: "docs/step-10-release.md", name: "step-10-release.md", kind: .file),
            ], omittedCount: id == "2f" ? 7412 : 0)
        }
        let model = FileTreeModel(root: root, loader: loader)
        await model.refresh()
        if id == "2e3" { try #require(model.branch == "Git 管理外") }
        if id == "2e4" { try #require(model.branch.isEmpty) }
        if id == "2i" {
            let view = FileTreeInspectorView(router: AppRouter(), session: nil, models: .constant([:]), files: FileTabDocuments())
            try await capture(view, frame: frame, output: output)
        } else {
            let expansion = Task { await model.expand("docs") }
            if id == "2g" {
                try await waitUntil { model.loading.contains("docs") }
            } else { await expansion.value }
            defer { expansion.cancel() }
            try await capture(FileTreeView(model: model, openPath: "docs/file-tree.md", open: { _, _ in }), frame: frame, output: output)
        }
        return id == "2f" ? "件数上限の表示を偽ローダーで再現。5000行の末尾へのスクロールは対象外"
            : id == "2e1" ? "ブランチ名は作業中の実ブランチ。見本の main と異なる"
            : id == "8L1" ? "ライトのツリー。キーボードフォーカス輪は対象外"
            : "実物のツリー。ルートのパスは worktree 内の撮影用データ"
    }

    private func renderSimulator(_ frame: Frame, output: URL) async throws -> String {
        let id = frame.id
        let displayID = UUID()
        let session = SessionID()
        let icon = NSApp.applicationIconImage
        if id == "7e" {
            let macos = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let applicationIcon = try #require(NSImage(contentsOf: macos
                .appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/512.png")))
            NSApp.applicationIconImage = applicationIcon
        }
        defer { if id == "7e" { NSApp.applicationIconImage = icon } }
        var states = [
            "iPhone 17 Pro": ["7f", "7g", "7nStopped"].contains(id) ? "Shutdown" : "Booted",
            "iPhone 17": "Shutdown", "iPhone 16e": "Shutdown",
            "iPad Air 13 インチ（M3）": "Booted",
        ]
        if id.hasPrefix("7Long") { states["iPad Pro 13-inch (M4)"] = id == "7LongStopped320" ? "Shutdown" : "Booted" }
        let fixture = HubCatalogFixture(states: states)
        if id == "7g" { await fixture.setState("Booting", udid: "iPhone 17") }
        let fake = HubTransport()
        let catalog = ["7k", "7ListingError"].contains(id) ? SimulatorCatalog(isXcodeAvailable: { id != "7k" }) { _, _ in
            .init(status: 72, output: Data(), errorOutput: Data((id == "7k"
                ? "xcrun: unable to find utility \"simctl\"" : "CoreSimulator のサービスに接続できません").utf8))
        } : fixture.catalog()
        let hub = SimulatorHub(catalog: catalog, refreshInterval: 60) {
            let connection = SimulatorDisplayConnection { fake }
            if id == "7h" {
                connection.policy = SimulatorPolicy(entries: [.init(xcodeBuild: "17C52",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", supportsInput: false)])
            }
            return connection
        }
        await hub.refresh()
        hub.select(udid: ["7k", "7ListingError"].contains(id) ? nil : id.hasPrefix("7Long")
            ? "iPad Pro 13-inch (M4)" : ["7f", "7g"].contains(id) ? "iPhone 17" : "iPhone 17 Pro", for: session)
        hub.setVisible(true, displayID: displayID, sessionID: session)
        defer { hub.disconnectAll() }
        if id == "7e" {
            let otherSession = SessionID()
            hub.select(udid: "iPhone 17 Pro", for: otherSession)
            hub.setVisible(true, displayID: UUID(), sessionID: otherSession)
        }
        if let connection = hub.connection(for: session) {
            try await waitUntil { fake.probeReply != nil }
            if id == "7l" {
                fake.failed?("シミュレーターの補助プロセスに接続できません")
                fake.failed?("自動の再接続後も応答がありません")
                try #require(connection.canReconnect)
            } else {
                let unverified = ["7j", "7j2", "7TrialInput520", "7LongTrialStale320"].contains(id)
                let capability = SimulatorBridgeCapability(
                    protocolVersion: id == "7m" ? SimulatorBridgeInterfaces.protocolVersion - 1 : SimulatorBridgeInterfaces.protocolVersion,
                    helperBuild: "検証", xcodeBuild: unverified ? "17D21" : "17C52",
                    coreSimulatorLoaded: true, simulatorKitLoaded: true)
                fake.probeReply?(capability)
                if unverified && id != "7j" {
                    hub.tryUnverified(displayID: displayID)
                    fake.probeReply?(capability)
                }
                if id != "7j" && id != "7m" {
                    let width = 402, height = 874
                    let surface = try #require(IOSurface(properties: [.width: width, .height: height,
                        .bytesPerElement: 4, .bytesPerRow: width * 4, .allocSize: width * height * 4,
                        .pixelFormat: 0x42475241]))
                    try #require(IOSurfaceLock(surface, [], nil) == 0)
                    let pixels = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt32.self)
                    for index in 0..<(width * height) { pixels[index] = 0xfff7f2f2 }
                    try #require(IOSurfaceUnlock(surface, [], nil) == 0)
                    fake.attachReply?(SimulatorDisplayInfo(udid: hub.selectedDevice(for: session)?.udid ?? "iPhone 17 Pro",
                        connectionGeneration: connection.generation.current, displayGeneration: 1,
                        surface: surface, pixelWidth: width, pixelHeight: height,
                        orientation: .portrait, surfaceIsRotated: false, pixelFormat: 0x42475241), nil)
                    try #require(connection.displayInfo != nil)
                    if ["7i", "7StaleInput520", "7LongTrialStale320"].contains(id), let info = connection.displayInfo {
                        try #require(IOSurfaceLock(surface, [], nil) == 0)
                        try #require(IOSurfaceUnlock(surface, [], nil) == 0)
                        connection.observeFrame(info, seed: IOSurfaceGetSeed(surface),
                                                at: Date().addingTimeInterval(-6))
                    }
                }
            }
        }
        let focused = ["7b", "7c", "7n", "8L3", "7TrialInput520", "7StaleInput520", "7LongInput320", "7LongTrialStale320"].contains(id)
        let content = SimulatorTabContent(hub: hub, sessionID: session, displayID: displayID,
            confirmsShutdown: id == "7e",
            sendsKeys: .constant(focused), showsDiagnostics: .constant(false),
            select: { _ in }, releaseFocus: {}, screenshot: {}, shutdown: {}, openSimulator: {})
            .overlay(alignment: .topLeading) {
                if id == "7i" {
                    SimulatorDiagnostics().background(DSColor.popoverBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.row))
                        .offset(x: 160, y: 34)
                }
            }
            .overlay(alignment: .top) {
                if id == "7e" {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.4)
                        SimulatorShutdownDialog(deviceName: "iPhone 17 Pro", displayCount: hub.displayCount(udid: "iPhone 17 Pro"),
                                                shutdown: {}, cancel: {})
                            .clipShape(RoundedRectangle(cornerRadius: DSRadius.l)).padding(.top, 70)
                    }
                }
            }
        try await capture(content, frame: frame, output: output, prepare: { host, window in
            let views = descendants(host)
            if id == "7r", let menu = views.first(where: { $0 is NSPopUpButton }) {
                window.makeFirstResponder(menu)
            }
            if let screen = views.compactMap({ $0 as? SimulatorScreenNSView }).first {
                if id == "7c" || id == "7c2" {
                    screen.showPointer(at: CGPoint(x: screen.bounds.width * 0.45, y: screen.bounds.height * 0.5),
                                       touching: id == "7c")
                }
            }
            if id == "7d", let menu = views.compactMap({ $0 as? NSPopUpButton }).first?.menu {
                let list = SimulatorMenuSnapshot(menu: menu)
                list.frame = NSRect(x: 8, y: 30, width: 310, height: CGFloat(menu.items.count * 26 + 10))
                host.addSubview(list)
            }

        })
        #expect(fake.inputs == 0)
        #expect(await fixture.mutations().isEmpty)
        let copy = Process()
        copy.executableURL = URL(fileURLWithPath: "/bin/cp")
        try FileManager.default.createDirectory(atPath: "/tmp/snap-sim", withIntermediateDirectories: true)
        copy.arguments = ["-R", destination(frame, output).path, "/tmp/snap-sim/"]
        try copy.run()
        copy.waitUntilExit()
        try #require(copy.terminationStatus == 0)
        return "偽の接続・単色 IOSurface と実物の表示部品。実端末操作なし。撮影直後に /tmp/snap-sim/ へコピー"
    }

    private func destination(_ frame: Frame, _ output: URL) -> URL {
        output.appendingPathComponent("\(frame.id)-\(frame.name).png")
    }

    private func capture<V: View>(_ content: V, frame: Frame, output: URL, prepare: ((NSView, NSWindow) -> Void)? = nil) async throws {
        let host = NSHostingView(rootView: content
            .frame(width: frame.width, height: frame.height)
            .background(DSColor.background)
            .environment(\.locale, Locale(identifier: frame.id == "3k" ? "en" : "ja"))
            .environment(\.colorScheme, frame.light ? .light : .dark))
        host.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: frame.width, height: frame.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: frame.light ? .aqua : .darkAqua)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        if frame.id.hasPrefix("1") { try await Task.sleep(for: .milliseconds(500)) }
        host.layoutSubtreeIfNeeded()
        prepare?(host, window)
        host.layoutSubtreeIfNeeded()
        // WebKit はホストの cacheDisplay に入らないので、完了した画像を合成する。
        let deadline = ContinuousClock.now + .seconds(10)
        if ["3d", "5a", "5e", "5h"].contains(frame.id) {
            try await waitUntil(deadline: deadline) { descendants(host).contains { $0 is WKWebView } }
        }
        var snapshots: [(NSImage, NSRect)] = []
        for web in descendants(host).compactMap({ $0 as? WKWebView }) {
            try await waitUntil(deadline: deadline) { !web.isLoading && web.url != nil }
            let ready = try await web.evaluateJavaScript("document.readyState")
            try #require(ready as? String == "complete")
            _ = try await web.callAsyncJavaScript(
                "await document.fonts.ready; return true",
                arguments: [:], in: nil, contentWorld: .defaultClient)
            let configuration = WKSnapshotConfiguration()
            configuration.rect = web.bounds
            configuration.snapshotWidth = NSNumber(value: Double(web.bounds.width * 2))
            configuration.afterScreenUpdates = false
            let image = try await web.takeSnapshot(configuration: configuration)
            var rect = host.convert(web.bounds, from: web)
            if host.isFlipped { rect.origin.y = host.bounds.height - rect.maxY }
            snapshots.append((image, rect))
        }
        host.layoutSubtreeIfNeeded()
        try saveBitmap(host, bounds: host.bounds, to: destination(frame, output), snapshots: snapshots)
        #expect(!window.isVisible)
    }

    private func saveBitmap(_ view: NSView, bounds: NSRect, to url: URL, snapshots: [(NSImage, NSRect)] = []) throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
            pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = bounds.size
        view.layoutSubtreeIfNeeded()
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: bounds, to: bitmap)
        }
        if !snapshots.isEmpty {
            let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            for (image, rect) in snapshots { image.draw(in: rect, from: .zero, operation: .copy, fraction: 1) }
            NSGraphicsContext.restoreGraphicsState()
        }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
        let decoded = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
        #expect(decoded.pixelsWide == Int(bounds.width * 2))
        #expect(decoded.pixelsHigh == Int(bounds.height * 2))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func waitUntil(deadline: ContinuousClock.Instant = .now + .seconds(3), _ condition: () -> Bool) async throws {
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard condition() else { throw Unavailable(reason: "画面外描画の準備が時間内に完了しなかった") }
    }
}


/// OS のメニューを開かず、本物の項目の文字・印を描く。
@MainActor private final class SimulatorMenuSnapshot: NSView {
    let sourceMenu: NSMenu
    init(menu: NSMenu) {
        self.sourceMenu = menu
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(DSColor.popoverBackground).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        for (index, item) in sourceMenu.items.enumerated() {
            let y = CGFloat(index * 26 + 5)
            if item.isSeparatorItem {
                NSColor(DSColor.separator).setFill()
                NSRect(x: 10, y: y + 12, width: bounds.width - 20, height: 1).fill()
            } else {
                if item.state == .on {
                    ("✓" as NSString).draw(at: NSPoint(x: 8, y: y + 5), withAttributes: [
                        .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(DSColor.textPrimary),
                    ])
                }
                item.image?.draw(in: NSRect(x: 22, y: y + 7, width: 10, height: 12))
                let title = item.attributedTitle ?? NSAttributedString(string: item.title,
                    attributes: [.font: NSFont.systemFont(ofSize: 13),
                                 .foregroundColor: NSColor(DSColor.textPrimary)])
                title.draw(at: NSPoint(x: item.representedObject == nil ? 12 : 40, y: y + 5))
            }
        }
    }
}
