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
    case closeChild(SessionID, ChildTab)
    /// セッション削除の確認を出す。
    case confirmSessionDeletion(SessionID)
    /// ⌘P：worktree のファイルを選んで開く。
    case openFile(SessionID)
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
    /// 上段タブ列と子タブ（02 C）。メニューの ⌘W・⌘1–9・⌃Tab からも触る。
    public let tabs: SessionTabStore
    /// 上段右端の「共通ターミナル」（worktree の外・ホームで開く）を前に出しているか。
    public var commonTerminalSelected = false
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

    public init(
        selectedSession: SessionID? = nil,
        viewMode: ViewMode = .single,
        mainRoute: MainRoute = .sessions,
        sidebarVisible: Bool = true,
        inspectorVisible: Bool = false,
        tabs: SessionTabStore = SessionTabStore()
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

    /// ⌃⌘T / ⌃⌘E：選択中セッションのターミナル・変更タブを開く（あれば前に出す）。単体表示へ切り替える。
    /// セッションを選んでいなければ、ターミナルは上段右端の共通ターミナルを出す。
    public func openChildTab(_ tab: ChildTab) {
        guard let selectedSession else {
            if tab == .terminal { commonTerminalSelected = true }
            return
        }
        viewMode = .single
        commonTerminalSelected = false
        tabs.updateLayout(for: selectedSession) { $0.open(tab) }
    }

    /// ⌃Tab / ⌃⇧Tab。
    public func cycleChildTab(by offset: Int) {
        guard viewMode == .single, !commonTerminalSelected, let selectedSession else { return }
        tabs.updateLayout(for: selectedSession) { $0.cycle(by: offset) }
    }

    /// ⌘\。
    public func toggleSplit() {
        guard viewMode == .single, !commonTerminalSelected, let selectedSession else { return }
        tabs.updateLayout(for: selectedSession) { $0.toggleSplit() }
    }

    /// ⌘W。子タブは閉じ（確認は画面側）、会話・グリッドはセッション削除の確認を出す。
    /// 何も対象が無ければ false（ウィンドウを閉じる標準動作に任せる）。
    @discardableResult
    public func requestClose() -> Bool {
        if viewMode == .single, commonTerminalSelected { return false }
        guard let target = tabs.closeTarget(selectedSession: selectedSession, viewMode: viewMode) else { return false }
        switch target {
        case .childTab(let tab):
            if let selectedSession { tabRequest = .closeChild(selectedSession, tab) }
        case .session(let id):
            tabRequest = .confirmSessionDeletion(id)
        }
        return true
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
    /// グリッドでは、すでに表示範囲にしているプロジェクトをもう一度押すと範囲を外す（従来のトグル）。
    public func selectProjectFromSidebar(_ projectID: ProjectID) {
        let wasScoped = gridFilterProjectID == projectID
        showProject(projectID)
        if viewMode == .grid, wasScoped {
            gridFilterProjectID = nil
        }
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
