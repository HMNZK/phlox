import Foundation
import AgentDomain
import DesignSystem
import Observation

public enum ViewMode: String, CaseIterable, Sendable {
    case single
    case grid
    case team
}

// GridColumns（グリッド列数モード）は DesignSystem/GridColumns.swift へ移設した
// （R1・task-26: Session ↔ Router 結合の切断。SessionFeature/DashboardFeature 双方が
// 参照する共有の表示設定のため下層へ降ろす）。

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
    }

    public func showSessions() {
        mainRoute = .sessions
    }

    /// サイドバーの表示/非表示をトグルする（Cmd+B・トグルボタン共通）。
    public func toggleSidebar() {
        sidebarVisible.toggle()
    }

    /// 右側インスペクターの表示/非表示をトグルする。
    public func toggleInspector() {
        inspectorVisible.toggle()
    }

    /// 表示モード（シングル／グリッド／チーム）を順送りで切り替える。
    public func toggleViewMode() {
        switch viewMode {
        case .single:
            viewMode = .grid
        case .grid:
            viewMode = .team
        case .team:
            viewMode = .single
        }
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
    /// - .grid / .team: 従来どおりグリッド絞り込みをトグルし .grid にする。
    public func selectProjectFromSidebar(_ projectID: ProjectID) {
        selectProject(projectID)
        switch viewMode {
        case .single:
            selectedSession = nil
        case .grid, .team:
            toggleGridFilter(projectID: projectID)
            viewMode = .grid
        }
    }
}
