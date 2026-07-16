import Foundation

/// セッション俯瞰の表示モード。グリッドは複数カードを同時表示、シングルは 1 件に集中する。
public enum OverviewMode: Equatable, Sendable {
    case grid
    case single
}
