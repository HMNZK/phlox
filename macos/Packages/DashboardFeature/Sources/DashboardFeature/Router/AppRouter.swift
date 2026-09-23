import Foundation
import AgentDomain
import DesignSystem
import Observation

public enum ViewMode: String, CaseIterable, Sendable {
    case single
    case grid
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
    /// サイドバーの表示状態。メニュー(Cmd+B)とビュー内トグルの双方から操作するため
    /// View の @State ではなく共有の Observable に置く。
    public var sidebarVisible: Bool
    /// 右側インスペクター（使用量サイドバー）の表示状態。
    public var inspectorVisible: Bool
    /// ターミナルパネルの表示状態。
    public var terminalPanelVisible: Bool
    /// エディタパネルの表示状態。
    public var editorPanelVisible: Bool
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
        inspectorVisible: Bool = false
    ) {
        self.selectedSession = selectedSession
        self.viewMode = viewMode
        self.mainRoute = mainRoute
        self.sidebarVisible = sidebarVisible
        self.inspectorVisible = inspectorVisible
        self.terminalPanelVisible = false
        self.editorPanelVisible = false
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

    /// ターミナルパネルの表示/非表示をトグルする。
    public func toggleTerminalPanel() {
        terminalPanelVisible.toggle()
    }

    /// エディタパネルの表示/非表示をトグルする。
    public func toggleEditorPanel() {
        editorPanelVisible.toggle()
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

    /// サイドバーでプロジェクト名を選択したときの遷移。表示モードで分岐する。
    /// - .single: プロジェクトを選択しセッション選択を解除（viewMode は .single のまま）。
    ///            → セッション未選択＋プロジェクト選択済みとなり、新規セッション開始画面が表示される。
    /// - .grid: 従来どおりグリッド絞り込みをトグルし .grid にする。
    public func selectProjectFromSidebar(_ projectID: ProjectID) {
        selectProject(projectID)
        switch viewMode {
        case .single:
            selectedSession = nil
        case .grid:
            toggleGridFilter(projectID: projectID)
            viewMode = .grid
        }
    }
}
