import Foundation
import AgentDomain
import DesignSystem
import SessionFeature

/// 対応待ち（承認待ち・質問待ち・エラー・無応答）の 1 件。完了の未読は対応待ちに含めない。
struct AttentionEntry: Equatable {
    let id: SessionID
    let kind: AttentionKind
    /// 今の状態に入った時刻。記録が無いセッションは nil。
    let since: Date?
}

/// ツールバーの「対応待ち」一覧（⌥⌘J）と「次の対応待ちへ」（⌘J）の並び。
enum AttentionQueue {
    /// 対応待ちだけを待ち時間の長い順（起点の古い順）に並べる。起点の無いものは末尾、同順位は入力順。
    static func ordered(_ candidates: [(id: SessionID, state: SessionDisplayState, since: Date?)]) -> [AttentionEntry] {
        candidates.enumerated()
            .compactMap { index, candidate -> (Int, AttentionEntry)? in
                guard let kind = candidate.state.attentionKind else { return nil }
                return (index, AttentionEntry(id: candidate.id, kind: kind, since: candidate.since))
            }
            .sorted { lhs, rhs in
                switch (lhs.1.since, rhs.1.since) {
                case let (l?, r?) where l != r: l < r
                case (_?, nil): true
                case (nil, _?): false
                default: lhs.0 < rhs.0
                }
            }
            .map(\.1)
    }

    /// ⌘J の行き先。一覧と同じ順で、今のセッションの次（末尾なら先頭へ戻る）。今のセッションが一覧に無ければ先頭。
    static func next(after current: SessionID?, in entries: [AttentionEntry]) -> SessionID? {
        guard !entries.isEmpty else { return nil }
        guard let current, let index = entries.firstIndex(where: { $0.id == current }) else {
            return entries[0].id
        }
        return entries[(index + 1) % entries.count].id
    }
}

extension DashboardViewModel {
    /// デスクトップから見える全セッションの対応待ち。待ち時間の長い順。
    var attentionEntries: [AttentionEntry] {
        AttentionQueue.ordered(desktopSessionNodes.map { node in
            (
                id: node.id,
                state: SessionDisplayState.resolve(node.displayStatus, hasUnseenCompletion: node.hasUnseenCompletion),
                since: node.statusEnteredAt
            )
        })
    }

    /// ⌘J（次の対応待ちへ）の行き先。
    public func nextAttentionSessionID(after current: SessionID?) -> SessionID? {
        AttentionQueue.next(after: current, in: attentionEntries)
    }

    public var hasAttention: Bool { !attentionEntries.isEmpty }

    /// 完了の未読（対応待ちとは別に数える）。
    var unseenCompletionNodes: [SessionNode] {
        desktopSessionNodes.filter {
            SessionDisplayState.resolve($0.displayStatus, hasUnseenCompletion: $0.hasUnseenCompletion) == .doneUnread
        }
    }

    private var desktopSessionNodes: [SessionNode] {
        sessionNodes.filter { isReachableFromUI($0.id, from: .desktop) }
    }
}
