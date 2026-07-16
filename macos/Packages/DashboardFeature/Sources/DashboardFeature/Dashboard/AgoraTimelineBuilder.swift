import Foundation
import AgentDomain
import SessionFeature

/// アゴラのフラットグループチャット構築（task-3）。
/// 参加者（`AgoraParticipantsPolicy` の結果）に含まれるソースだけを、
/// 既存の `TeamTimelineModel.merge` の規則（timestamp 昇順・同値/欠損の tiebreak は
/// sources 出現順→transcript 順）で時系列フラットマージする。merge 本体は変更しない。
///
/// 契約（tasks/task-3.md / AcceptanceAgoraTimelineTests）:
/// - participants に無いソースの発言は結果に含めない。
/// - participants にあるが sources に無い ID は無視する（クラッシュしない）。
/// - sources の与えられた順序を保って merge に委譲する（tiebreak の決定性）。
public enum AgoraTimelineBuilder {
    public static func build(
        sources: [AgentTimelineSource],
        participants: [SessionID]
    ) -> [TeamTimelineItem] {
        let participantIDs = Set(participants)
        let filteredSources = sources
            .filter { participantIDs.contains($0.id) }
            .map { source in
                TeamTimelineSource(
                    id: source.id,
                    displayName: source.displayName,
                    agentDescriptor: source.agentDescriptor,
                    messages: source.messages
                )
            }
        return TeamTimelineModel.merge(filteredSources)
    }
}
