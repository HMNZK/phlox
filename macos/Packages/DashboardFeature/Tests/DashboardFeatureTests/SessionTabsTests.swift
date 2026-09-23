import Foundation
import Testing
import AgentDomain
import DesignSystem
@testable import DashboardFeature

@Suite("子タブの並びと分割（02 C）")
struct SessionTabLayoutTests {

    @Test("新しいセッションは会話タブだけで、会話は閉じられない")
    func conversationCannotBeClosed() {
        var layout = SessionTabLayout()

        let closed = layout.close(.conversation)

        #expect(closed == false)
        #expect(layout.tabs == [.conversation])
        #expect(layout.selected == .conversation)
    }

    @Test("開いている子タブを閉じると左隣を選ぶ")
    func closingSelectedTabSelectsLeftNeighbor() {
        var layout = SessionTabLayout()
        layout.open(.terminal)
        layout.open(.changes)
        layout.select(.terminal)

        layout.close(.terminal)

        #expect(layout.tabs == [.conversation, .changes])
        #expect(layout.selected == .conversation)
    }

    @Test("既に開いている子タブを開くと、足さずに前に出す")
    func openingExistingTabBringsItForward() {
        var layout = SessionTabLayout()
        layout.open(.terminal)
        layout.select(.conversation)

        layout.open(.terminal)

        #expect(layout.tabs == [.conversation, .terminal])
        #expect(layout.selected == .terminal)
    }

    @Test("⌃Tab は端で先頭へ、⌃⇧Tab は先頭で末尾へ回る")
    func cycleWrapsAround() {
        var layout = SessionTabLayout()
        layout.open(.terminal)
        layout.open(.changes)

        layout.cycle(by: 1)
        let afterForward = layout.selected
        layout.cycle(by: -1)
        let afterBackward = layout.selected

        #expect(afterForward == .conversation)
        #expect(afterBackward == .changes)
    }

    @Test("⌘\\ は現在のタブを右に出し、左に会話を残す（C2）。もう一度で解除")
    func toggleSplitMovesCurrentTabRight() {
        var layout = SessionTabLayout()
        layout.open(.changes)

        layout.toggleSplit()
        let splitLeft = layout.left
        let splitRight = layout.right
        let splitSelected = layout.selected
        layout.toggleSplit()

        #expect(splitLeft == .conversation)
        #expect(splitRight == .changes)
        #expect(splitSelected == .changes)
        #expect(layout.right == nil)
        #expect(layout.left == .changes)
    }

    @Test("分割中にもう一方の区画のタブを選んでも左右は入れ替わらない")
    func selectingOtherPaneKeepsPositions() {
        var layout = SessionTabLayout()
        layout.open(.changes)
        layout.splitRight(.changes)

        layout.select(.conversation)

        #expect(layout.left == .conversation)
        #expect(layout.right == .changes)
        #expect(layout.selected == .conversation)
    }

    @Test("分割中に出ていないタブを選ぶと、操作中の区画の中身を差し替える")
    func selectingHiddenTabReplacesFocusedPane() {
        var layout = SessionTabLayout()
        layout.open(.changes)
        layout.open(.terminal)
        layout.select(.changes)
        layout.splitRight(.changes)

        layout.select(.terminal)

        #expect(layout.left == .conversation)
        #expect(layout.right == .terminal)
    }

    @Test("右の区画のタブを閉じると分割が解ける")
    func closingRightPaneUnsplits() {
        var layout = SessionTabLayout()
        layout.open(.terminal)
        layout.splitRight(.terminal)

        layout.close(.terminal)

        #expect(layout.right == nil)
        #expect(layout.selected == .conversation)
    }

    @Test("子タブがひとつだけなら分割しない")
    func splitNeedsTwoTabs() {
        var layout = SessionTabLayout()

        layout.toggleSplit()

        #expect(layout.right == nil)
        #expect(layout.left == .conversation)
    }
}

@Suite("上段のセッションタブ列（02 C）")
struct SessionTabsSnapshotTests {
    private let project = ProjectID()
    private let first = SessionID()
    private let second = SessionID()
    private let third = SessionID()

    @Test("保存が無いプロジェクトは、そのプロジェクトのセッションをすべてタブにする")
    func defaultsToAllSessions() {
        let snapshot = SessionTabsSnapshot()

        let tabs = snapshot.sessionTabs(in: project, candidates: [first, second])

        #expect(tabs == [first, second])
    }

    @Test("✕ で閉じたセッションはタブ列から消え、選び直すと元の位置に戻る")
    func closedTabReappearsWhenRevealed() {
        var snapshot = SessionTabsSnapshot()
        let candidates = [first, second, third]

        _ = snapshot.closeSessionTab(first, in: project, candidates: candidates)
        let afterClose = snapshot.sessionTabs(in: project, candidates: candidates)
        snapshot.reveal(first, in: project, candidates: candidates)
        let afterReveal = snapshot.sessionTabs(in: project, candidates: candidates)

        #expect(afterClose == [second, third])
        #expect(afterReveal == [first, second, third])
    }

    @Test("閉じたタブの右隣を次に選ぶ。末尾なら左隣")
    func closeReturnsNeighbor() {
        var snapshot = SessionTabsSnapshot()
        let candidates = [first, second, third]

        let afterMiddle = snapshot.closeSessionTab(second, in: project, candidates: candidates)
        let afterLast = snapshot.closeSessionTab(third, in: project, candidates: candidates)
        let afterOnly = snapshot.closeSessionTab(first, in: project, candidates: candidates)

        #expect(afterMiddle == third)
        #expect(afterLast == first)
        #expect(afterOnly == nil)
    }

    @Test("あとから増えたセッションは保存済みの並びの後ろに付く")
    func newSessionsAppendAfterSavedOrder() {
        var snapshot = SessionTabsSnapshot()
        snapshot.reveal(second, in: project, candidates: [second, first])

        let tabs = snapshot.sessionTabs(in: project, candidates: [first, second, third])

        #expect(tabs == [second, first, third])
    }

    @Test("削除したセッションは並びと子タブの記録から消える")
    func forgetDropsSession() {
        var snapshot = SessionTabsSnapshot()
        snapshot.reveal(first, in: project, candidates: [first, second])
        snapshot.sessions[first] = SessionTabLayout()

        snapshot.forget(first)

        #expect(snapshot.projects[project]?.order == [second])
        #expect(snapshot.sessions[first] == nil)
    }
}

@Suite("隠れたタブの対応待ち（C7）")
struct HiddenAttentionSummaryTests {

    @Test("種類がひとつならその状態、件数つき")
    func singleKind() {
        let summary = HiddenAttentionSummary.make(hiddenStates: [.question, .running, .question])

        #expect(summary == HiddenAttentionSummary(kind: .question, count: 2))
    }

    @Test("種類が混ざれば種類なし（「対応待ち」と出す）")
    func mixedKinds() {
        let summary = HiddenAttentionSummary.make(hiddenStates: [.approval, .error])

        #expect(summary == HiddenAttentionSummary(kind: nil, count: 2))
    }

    @Test("対応待ちが隠れていなければ出さない")
    func noneHidden() {
        #expect(HiddenAttentionSummary.make(hiddenStates: [.running, .done]) == nil)
    }
}

@Suite("タブの保存と ⌘W の振り分け")
@MainActor
struct SessionTabStoreTests {

    @Test("子タブと分割は保存され、次の起動で戻る")
    func layoutPersists() throws {
        let suite = "phlox.tests.sessionTabs.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SessionID()

        SessionTabStore(defaults: defaults).updateLayout(for: session) {
            $0.open(.changes)
            $0.toggleSplit()
        }
        let restored = SessionTabStore(defaults: defaults).layout(for: session)

        #expect(restored.tabs == [.conversation, .changes])
        #expect(restored.right == .changes)
    }

    @Test("単体表示で会話以外の子タブを選んでいれば ⌘W はそのタブを閉じる")
    func closeTargetsChildTab() {
        let store = SessionTabStore()
        let session = SessionID()
        store.updateLayout(for: session) { $0.open(.terminal) }

        let target = store.closeTarget(selectedSession: session, viewMode: .single)

        #expect(target == .childTab(.terminal))
    }

    @Test("会話タブでは ⌘W はセッション（確認つきの削除）、グリッドではタイルを外す")
    func closeTargetsSession() {
        let store = SessionTabStore()
        let session = SessionID()
        store.updateLayout(for: session) { $0.open(.terminal) }

        let inGrid = store.closeTarget(selectedSession: session, viewMode: .grid)
        store.updateLayout(for: session) { $0.select(.conversation) }
        let inConversation = store.closeTarget(selectedSession: session, viewMode: .single)

        #expect(inGrid == .gridTile(session))
        #expect(inConversation == .session(session))
    }

    @Test("⌘W はセッション削除を直接せず、確認の要求を出す")
    func requestCloseAsksForConfirmation() {
        let session = SessionID()
        let router = AppRouter(selectedSession: session)

        let handled = router.requestClose()

        #expect(handled)
        #expect(router.tabRequest == .confirmSessionDeletion(session))
    }

    @Test("⌃⌘T は選択中セッションのターミナルタブを開き、単体表示にする")
    func openChildTabFromMenu() {
        let session = SessionID()
        let router = AppRouter(selectedSession: session, viewMode: .grid)

        router.openChildTab(.terminal)

        #expect(router.viewMode == .single)
        #expect(router.tabs.layout(for: session).selected == .terminal)
    }

    @Test("セッション未選択の ⌃⌘T は共通ターミナルを出す")
    func openTerminalWithoutSessionShowsCommonTerminal() {
        let router = AppRouter()

        router.openChildTab(.terminal)

        #expect(router.commonTerminalSelected)
    }
}

@Suite("セッションのターミナルタブ")
@MainActor
struct SessionTerminalStoreTests {

    @Test("ターミナルタブのシェルはそのセッションの worktree で起動し、同じセッションでは使い回す")
    func terminalStartsInSessionWorktree() async throws {
        let pty = MockPTYManager()
        let store = SessionTerminalStore { workingDirectory in
            TerminalPanelSession(controller: UserTerminalController(
                pty: pty,
                shellPath: "/bin/sh",
                workingDirectory: workingDirectory,
                environment: ["PATH": "/usr/bin:/bin"]
            ))
        }
        let session = SessionID()

        let terminal = store.terminal(for: session, workingDirectory: "/tmp/phlox-worktrees/tsubaki")
        let again = store.terminal(for: session, workingDirectory: "/tmp/phlox-worktrees/tsubaki")
        await terminal.ensureStarted()

        #expect(terminal === again)
        #expect(pty.spawnCalls.map(\.workingDirectory) == ["/tmp/phlox-worktrees/tsubaki"])
        #expect(store.isRunning(session))
        await store.close(session)?.value
    }

    @Test("セッションの作業場所が変わったら、旧い場所のシェルを止めて新しい場所で作り直す")
    func workspaceChangeRecreatesShell() async throws {
        let pty = MockPTYManager()
        let store = SessionTerminalStore { workingDirectory in
            TerminalPanelSession(controller: UserTerminalController(
                pty: pty,
                shellPath: "/bin/sh",
                workingDirectory: workingDirectory,
                environment: ["PATH": "/usr/bin:/bin"]
            ))
        }
        let session = SessionID()
        let old = store.terminal(for: session, workingDirectory: "/tmp/old-worktree")
        await old.ensureStarted()

        let moved = store.terminal(for: session, workingDirectory: "/tmp/new-worktree")
        await moved.ensureStarted()
        try await waitUntil { old.controller.isRunning == false }

        #expect(moved !== old)
        #expect(old.controller.isRunning == false)
        #expect(pty.spawnCalls.map(\.workingDirectory) == ["/tmp/old-worktree", "/tmp/new-worktree"])
        await store.close(session)?.value
    }

    @Test("タブを閉じるとシェルを止め、次に開くと新しいシェルになる")
    func closingStopsShell() async throws {
        let pty = MockPTYManager()
        let store = SessionTerminalStore { workingDirectory in
            TerminalPanelSession(controller: UserTerminalController(
                pty: pty,
                shellPath: "/bin/sh",
                workingDirectory: workingDirectory,
                environment: ["PATH": "/usr/bin:/bin"]
            ))
        }
        let session = SessionID()
        let first = store.terminal(for: session, workingDirectory: "/tmp/wt")
        await first.ensureStarted()

        await store.close(session)?.value
        let reopened = store.terminal(for: session, workingDirectory: "/tmp/wt")

        #expect(first.controller.isRunning == false)
        #expect(store.isRunning(session) == false)
        #expect(reopened !== first)
    }
}

/// 旧いシェルの停止は置き場の外で非同期に進むため、観測できるまで待つ。
@MainActor
private func waitUntil(timeout: Duration = .seconds(1), _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { throw WaitTimeout() }
        await Task.yield()
    }
}

private struct WaitTimeout: Error {}

@Suite("⌘P で選んだファイルの相対パス")
struct FileOpenRelativePathTests {

    @Test("worktree の中なら直下からの相対パス、外なら開かない")
    func relativePathInsideRootOnly() {
        let root = "/tmp/phlox-root"

        let inside = DashboardView.relativePath(of: URL(fileURLWithPath: "/tmp/phlox-root/Sources/App.swift"), under: root)
        let outside = DashboardView.relativePath(of: URL(fileURLWithPath: "/tmp/phlox-rootless/App.swift"), under: root)

        #expect(inside == "Sources/App.swift")
        #expect(outside == nil)
    }
}

@Suite("上段タブのドラッグ並べ替え")
struct SessionTabReorderTests {
    private let project = ProjectID()
    private let first = SessionID()
    private let second = SessionID()
    private let third = SessionID()

    @Test("右のタブへ落とすとその後ろ、左のタブへ落とすとその前に入る")
    func dropInsertsRelativeToDirection() {
        var snapshot = SessionTabsSnapshot()
        let candidates = [first, second, third]

        snapshot.moveSessionTab(first, onto: third, in: project, candidates: candidates)
        let afterRight = snapshot.sessionTabs(in: project, candidates: candidates)
        snapshot.moveSessionTab(first, onto: second, in: project, candidates: candidates)
        let afterLeft = snapshot.sessionTabs(in: project, candidates: candidates)

        #expect(afterRight == [second, third, first])
        #expect(afterLeft == [first, second, third])
    }
}
