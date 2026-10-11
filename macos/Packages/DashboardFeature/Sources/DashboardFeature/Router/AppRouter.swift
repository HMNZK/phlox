import Foundation
import AgentDomain
import DesignSystem
import Observation

public enum ViewMode: String, CaseIterable, Sendable {
    case single
    case grid
}

/// メニューから画面へ渡す要求。
public enum TabRequest: Equatable, Sendable {
    /// 子タブを閉じる（ターミナルはシェル終了の確認、未保存ファイルは破棄の確認を挟む）。
    case closeChild(ProjectID, ProjectTab)
    /// セッション削除の確認を出す。
    case confirmSessionDeletion(SessionID)
    /// ⌘P：プロジェクトのファイルを選んで開く。
    case openFile(ProjectID)
    case confirmProjectDeletion(ProjectID)
    /// グリッドのタイルを外す（⌘W・タイルの ✕）。
    case removeFromGrid(SessionID)
}

/// メニューバーの「セッション」メニューから、サイドバーの行の操作を画面へ渡す要求（キーボードだけで届くように）。
public enum SidebarRequest: Equatable, Sendable {
    /// 名前を変更（サイドバーが見えていれば行の中で、見えなければアラートで）。
    case renameSession(SessionID)
    /// 別のプロジェクトへ移動・割り当て（再起動の確認を挟む）。
    case moveSession(SessionID, ProjectID)
    /// フォルダを選んで作業場所を変える（選んだ後に再起動の確認を挟む）。
    case changeFolder(SessionID)
}

public enum InspectorTab: Hashable, CaseIterable, Sendable {
    case session
    case files
    case usage
}

public enum MainRoute: String, Sendable {
    case sessions
}

/// アプリ内ナビゲーション状態。NavigationSplitView のサイドバー選択と表示モードを保持する。
@MainActor
@Observable
public final class AppRouter {
    public var selectedSession: SessionID?
    public var viewMode: ViewMode
    public var gridFilterProjectID: ProjectID?
    /// ユーザーが明示的に選択中のプロジェクト（R4: セレクトカードの表示条件）。
    /// サイドバーのプロジェクト行クリックで設定する。非永続。
    public var selectedProjectID: ProjectID?
    public var mainRoute: MainRoute
    /// サイドバーの表示状態。メニュー（⌃⌘S）とビュー内トグルの双方から操作するため
    /// View の @State ではなく共有の Observable に置く。
    public var sidebarVisible: Bool
    /// 右側インスペクター（使用量サイドバー）の表示状態。
    public var inspectorVisible: Bool
    /// インスペクタの「セッション / 使用量」（07）。
    public var inspectorTab: InspectorTab = .usage
    /// プロジェクトタブの右クリック「プロジェクト名を変更…」。サイドバーがその行を編集に入れる。
    public var projectRenameRequest: ProjectID?
    /// プロジェクトの項目・選択・分割。メニューと画面で共有する。
    public let tabs: ProjectTabStore
    /// ブラウザのページと履歴は、子タブを閉じるまでだけ保持する。
    private(set) var browsers: [ProjectID: BrowserTabModel] = [:]
    /// 「新しいタブ」の選択肢（⌘T・＋）を開いているか。
    public var newTabChooserPresented = false
    /// 画面側でしか処理できない要求（確認ダイアログ・ファイル選択・シェル終了）。DashboardView が受けて nil に戻す。
    public var tabRequest: TabRequest?
    /// サイドバーの行の操作の要求。DashboardView が受けて nil に戻す。
    public var sidebarRequest: SidebarRequest?
    /// サイドバーを横に並べる幅が無いか（開いていても自動で隠す）。DashboardView がウィンドウ幅から決める。
    public var sidebarLacksRoom = false
    /// 自動で隠れたサイドバーを中央の上に一時的に重ねて出しているか（⌃⌘S）。
    public var sidebarPeeking = false
    /// ツールバーの「対応待ち」一覧を開いているか（⌥⌘J）。
    public var attentionListPresented = false
    /// メニューの「プロジェクトを追加…」（⌘O）が押された。フォルダ選択を持つ DashboardView が受けて false に戻す。
    public var addProjectRequested = false
    /// 新規セッションの表（⌘N）を開いているか。選択中のプロジェクトへ作る。
    public var newSessionTablePresented = false

    public init(
        selectedSession: SessionID? = nil,
        viewMode: ViewMode = .single,
        mainRoute: MainRoute = .sessions,
        sidebarVisible: Bool = true,
        inspectorVisible: Bool = false,
        tabs: ProjectTabStore = ProjectTabStore()
    ) {
        self.selectedSession = selectedSession
        self.viewMode = viewMode
        self.mainRoute = mainRoute
        self.sidebarVisible = sidebarVisible
        self.inspectorVisible = inspectorVisible
        self.tabs = tabs
    }

    public func showSessions() {
        mainRoute = .sessions
    }

    /// サイドバーの表示/非表示をトグルする（⌃⌘S・トグルボタン共通）。
    /// 横に並べる幅が無いときは、一時表示（重ね表示）を切り替える。手動で隠していても 1 回で出す。
    public func toggleSidebar() {
        if sidebarLacksRoom {
            sidebarVisible = true
            sidebarPeeking.toggle()
        } else {
            sidebarVisible.toggle()
            sidebarPeeking = false
        }
    }

    /// 右側インスペクターの表示/非表示をトグルする。
    public func toggleInspector() {
        inspectorVisible.toggle()
    }

    /// 使用量チップのクリック（07）。インスペクタを開いて「使用量」を前に出す。
    public func showUsageInInspector() {
        inspectorTab = .usage
        inspectorVisible = true
    }

    /// ⌃⌘B：インスペクタを開いてファイルツリーを表示する。
    public func showFilesInInspector() {
        inspectorTab = .files
        inspectorVisible = true
    }

    public func selectTab(_ tab: ProjectTab, in projectID: ProjectID) {
        selectedProjectID = projectID
        tabs.updateLayout(for: projectID) { $0.select(tab) }
        if case .chat(let id) = tab { selectedSession = id }
        else if tab == .newChat { selectedSession = nil }
    }

    public func showNewChat(projectID: ProjectID) {
        viewMode = .single
        selectedProjectID = projectID
        tabs.updateLayout(for: projectID) { $0.open(.newChat) }
        selectedSession = nil
    }

    public func completeNewChat(sessionID: SessionID, projectID: ProjectID) {
        tabs.updateLayout(for: projectID) { $0.close(.newChat); $0.open(.chat(sessionID)) }
        selectTab(.chat(sessionID), in: projectID)
    }

    public func openTerminalTab() {
        guard selectedProjectID != nil else { return }
        openChildTab(.terminal(TerminalTabID()))
    }

    public func openChildTab(_ tab: ProjectTab) {
        guard let projectID = selectedProjectID else { return }
        viewMode = .single
        if tab == .browser, browsers[projectID] == nil { browsers[projectID] = BrowserTabModel() }
        tabs.updateLayout(for: projectID) { $0.open(tab) }
        if case .chat(let id) = tab { selectedSession = id }
        else if tab == .newChat { selectedSession = nil }
    }

    func openBrowser(_ url: URL, for projectID: ProjectID) {
        guard selectedProjectID == projectID else { return }
        openChildTab(.browser)
        browsers[projectID]?.open(url)
    }

    func closeBrowser(for projectID: ProjectID) {
        browsers.removeValue(forKey: projectID)?.close()
    }

    public func forgetProject(_ projectID: ProjectID, terminals: ProjectTerminalStore?, simulatorHub: SimulatorHub?) async {
        FileTabDocumentRegistry.shared.beginProjectChanges(for: [projectID])
        defer { FileTabDocumentRegistry.shared.endProjectChanges(for: [projectID]) }
        await FileTabDocumentRegistry.shared.invalidateAndWait(for: [projectID])
        tabs.forgetProject(projectID)
        closeBrowser(for: projectID)
        simulatorHub?.removeProject(projectID)
        await terminals?.closeProject(projectID)
        if selectedProjectID == projectID { selectedProjectID = nil; selectedSession = nil }
    }

    public func zoomFrontBrowser(by steps: Int?) -> Bool {
        guard viewMode == .single, let id = selectedProjectID,
              tabs.layout(for: id).selected == .browser, let browser = browsers[id] else { return false }
        browser.zoom(by: steps)
        return true
    }

    public func cycleChildTab(by offset: Int, chats: [ProjectTab]) {
        guard viewMode == .single, let id = selectedProjectID else { return }
        tabs.updateLayout(for: id) { $0.cycle(by: offset, chats: chats) }
        if let selected = tabs.layout(for: id).selected { selectTab(selected, in: id) }
    }

    public func toggleSplit(chats: [ProjectTab] = []) {
        guard viewMode == .single, let id = selectedProjectID else { return }
        tabs.updateLayout(for: id) { $0.toggleSplit(chats: chats) }
        if let selected = tabs.layout(for: id).selected { selectTab(selected, in: id) }
    }

    @discardableResult
    public func requestClose() -> Bool {
        guard let target = tabs.closeTarget(projectID: selectedProjectID, selectedSession: selectedSession, viewMode: viewMode) else { return false }
        return requestClose(target)
    }

    @discardableResult
    public func requestClose(_ target: CloseCommandTarget) -> Bool {
        switch target {
        case .tab(let tab):
            if let selectedProjectID { tabRequest = .closeChild(selectedProjectID, tab) }
        case .session(let id): tabRequest = .confirmSessionDeletion(id)
        case .project(let id): tabRequest = .confirmProjectDeletion(id)
        case .gridTile(let id): tabRequest = .removeFromGrid(id)
        }
        return true
    }

    /// 上段のプロジェクトタブを、サイドバーと同じ順で巡回する。
    public func cycleProject(by offset: Int, ordered projects: [ProjectID]) {
        guard !projects.isEmpty else { return }
        let index = selectedProjectID.flatMap { projects.firstIndex(of: $0) } ?? (offset > 0 ? -1 : 0)
        let count = projects.count
        selectProjectFromSidebar(projects[((index + offset % count) % count + count) % count])
    }

    /// 表示モード（単体／グリッド）を巡回する（⌃⌘G）。直接選ぶのは ⌃⌘1 / ⌃⌘2 で `viewMode` に代入する。
    public func toggleViewMode() {
        viewMode = viewMode == .single ? .grid : .single
    }

    /// プロジェクトを選択状態にする（nil で解除）。
    public func selectProject(_ projectID: ProjectID?) {
        selectedProjectID = projectID
    }

    /// 指定セッションをシングルビューで開く（R7: エージェントビューからのドリルダウン）。
    public func openSingle(sessionID: SessionID) {
        selectedSession = sessionID
        viewMode = .single
    }

    /// グリッド絞り込み対象ワークスペースをトグルする。同一 ID なら解除、異なれば差し替え。
    public func toggleGridFilter(projectID: ProjectID) {
        if gridFilterProjectID == projectID {
            gridFilterProjectID = nil
        } else {
            gridFilterProjectID = projectID
        }
    }

    public func clearGridFilter() {
        gridFilterProjectID = nil
    }

    /// サイドバーでプロジェクト行をクリックしたときの遷移（`showProject`）。
    /// もう一度押しても範囲は外さない。外すのは ⌘クリック（`clearProjectScope`）だけ（03 M。2026-09-24 ユーザー決定）。
    public func selectProjectFromSidebar(_ projectID: ProjectID) {
        showProject(projectID)
    }

    /// サイドバーでプロジェクト行を選ぶ（↑↓・クリック）。選んだプロジェクトがグリッドの表示範囲になる（03 行の規則）。
    /// 単体表示ではセッションの選択を外して起動カードを出す（ADR 0086）。
    public func showProject(_ projectID: ProjectID) {
        selectProject(projectID)
        gridFilterProjectID = projectID
        if viewMode == .single {
            selectedSession = nil
        }
    }

    /// ⌘クリック: 選択中のプロジェクトを外し、グリッドの範囲を「すべて」に戻す（03 キーボード）。
    public func clearProjectScope() {
        selectProject(nil)
        gridFilterProjectID = nil
    }
}
