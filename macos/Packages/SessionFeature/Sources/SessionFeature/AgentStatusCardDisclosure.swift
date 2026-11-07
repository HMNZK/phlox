import Foundation

// エージェント状態カードの開閉と件数の規則（設計 §5。純粋な値。View の状態として持ち、保存しない）。
// 自動の開閉は組み立ての結果（実行中か・進行中のタスクか）から決め、手で開閉したものは
// カード id と行 id（タスクは `task-<タスク id>`）の組で覚える。

struct AgentStatusCardDisclosure: Equatable {
    /// 作業が多い行で最初に出す件数（要件 FR-15）。
    static let initialEntryLimit = 30

    private struct Key: Hashable {
        let cardID: String
        let rowID: String
    }

    private var overrides: [Key: Bool] = [:]
    private var limits: [Key: Int] = [:]

    // MARK: - 開閉

    /// 手の開閉が無いときの開閉。実行中のカードで、進行中のタスクと、今の作業があるタスク外の行だけ開く。
    /// 終わったカードは全部閉じる（FR-8）。
    static func isAutoExpanded(_ row: AgentStatusRow, in card: AgentStatusCard) -> Bool {
        guard card.header.isLive else { return false }
        switch row {
        case .task(let task):
            return task.state == .inProgress
        case .outside(let group):
            let hasInProgressTask = card.rows.contains {
                if case .task(let task) = $0 { task.state == .inProgress } else { false }
            }
            let hasRunningAction = group.entries.contains {
                if case .action(let action) = $0 { action.isRunning } else { false }
            }
            return !hasInProgressTask || hasRunningAction
        }
    }

    func isExpanded(_ row: AgentStatusRow, in card: AgentStatusCard) -> Bool {
        overrides[Key(cardID: card.id, rowID: row.id)] ?? Self.isAutoExpanded(row, in: card)
    }

    /// 今の見た目と反対にして、手の状態として覚える。
    mutating func toggle(_ row: AgentStatusRow, in card: AgentStatusCard) {
        overrides[Key(cardID: card.id, rowID: row.id)] = !isExpanded(row, in: card)
    }

    // MARK: - 件数

    /// 行で今出す件数の上限。
    func entryLimit(_ row: AgentStatusRow, in card: AgentStatusCard) -> Int {
        limits[Key(cardID: card.id, rowID: row.id)] ?? Self.initialEntryLimit
    }

    /// 「さらに表示」: もう 30 件出す。
    mutating func showMore(_ row: AgentStatusRow, in card: AgentStatusCard) {
        limits[Key(cardID: card.id, rowID: row.id)] = entryLimit(row, in: card) + Self.initialEntryLimit
    }

    /// 新しい順に `limit` 件。古い側が `hidden` 件（順序は時系列のまま）。
    static func window(_ entries: [AgentStatusEntry], limit: Int) -> (visible: [AgentStatusEntry], hidden: Int) {
        let visible = entries.suffix(max(0, limit))
        return (Array(visible), entries.count - visible.count)
    }
}

extension AgentStatusRow {
    var entries: [AgentStatusEntry] {
        switch self {
        case .task(let task): task.entries
        case .outside(let group): group.entries
        }
    }

    /// 開ける行か。作業の無いタスク（未着手など）は開けない。
    var isExpandable: Bool { !entries.isEmpty }
}

extension AgentStatusCard {
    /// 描画の予算に数える、開いている作業の行の数（自動で開く行だけ。手で開いた分は View の状態なので数えない）。
    var openEntryCount: Int {
        rows.reduce(0) { total, row in
            AgentStatusCardDisclosure.isAutoExpanded(row, in: self)
                ? total + min(row.entries.count, AgentStatusCardDisclosure.initialEntryLimit)
                : total
        }
    }
}
