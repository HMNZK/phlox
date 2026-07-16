import Foundation
import AgentDomain
import SessionFeature

/// アゴラ（旧チーム表示）のグループチャットに参加させるセッションの選別（task-3）。
///
/// 暫定既定（ユーザー確定待ち・decision-log 2026-07-11 参照）:
/// 「全ルートセッション＋各ルートの直接の子」。深さ2以上（孫以下＝作業用 spawn）は表示しない。
/// Agora 本体 run で範囲を確定・差し替えるため、判定はこの1関数に隔離する。
///
/// 契約（tasks/task-3.md / AcceptanceAgoraTimelineTests、討論モードは tasks/task-5.md /
/// AcceptanceAgoraDiscussionUITests）:
/// - `orderedIDs` の順序を保った部分列を返す（並べ替えない）。
/// - `discussionParticipants` 非 nil（討論中）: その集合に属する ID のみ（階層は無視。孫でも参加者なら含める）。
/// - `discussionParticipants` nil（非討論）: 現行どおりルート＋直接の子。
///   - `parentByID` にキーが無い ID はルート → 含める。
///   - 親の親が無い（親がルート扱いの）ID は直接の子 → 含める。それ以外（孫以下・循環）→ 除外。
public enum AgoraParticipantsPolicy {
    public static func participants(
        orderedIDs: [SessionID],
        parentByID: [SessionID: SessionID],
        discussionParticipants: Set<SessionID>? = nil
    ) -> [SessionID] {
        if let discussionParticipants {
            return orderedIDs.filter { discussionParticipants.contains($0) }
        }
        return orderedIDs.filter { id in
            guard let parentID = parentByID[id], parentID != id else {
                return parentByID[id] == nil
            }
            return parentByID[parentID] == nil
        }
    }

    /// 対象プロジェクトに属する全ルート木を、forest の順序を保って flatten する。
    ///
    /// `TeamTimelineView` の source 給餌用。ここでは参加者を絞らず、プロジェクト内の全階層を返す。
    /// ルート＋直接の子という参加者選別は `participants(orderedIDs:parentByID:)` 側に集約する。
    public static func orderedProjectSessionIDs(
        forest: [SessionTreeNode],
        projectID: ProjectID
    ) -> [SessionID] {
        forest.flatMap { root -> [SessionID] in
            guard root.projectID == projectID else { return [] }
            return root.flattenedProjectIDs(projectID: projectID)
        }
    }
}

private extension SessionTreeNode {
    func flattenedProjectIDs(projectID: ProjectID) -> [SessionID] {
        let ownIDs = self.projectID == projectID ? [id] : []
        return ownIDs + children.flatMap { $0.flattenedProjectIDs(projectID: projectID) }
    }
}
