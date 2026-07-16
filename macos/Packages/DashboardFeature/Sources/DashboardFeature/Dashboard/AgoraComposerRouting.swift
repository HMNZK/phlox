import Foundation

/// アゴラ composer の送信先判定（PM 実装・完成品。task-5 はこれを利用する）。
/// 討論中はユーザー発言として合流、非討論で開始可能なら議題投入、
/// 討論を開始できない文脈（討論非対応の選択等）は従来の根宛て送信に温存する。
public enum AgoraComposerAction: Equatable, Sendable {
    case startDiscussion(agenda: String)
    case discussionUtterance(String)
    case legacyRootSend(String)
}

public enum AgoraComposerRouting {
    public static func action(
        phase: AgoraDiscussionPhase?,
        canStartDiscussion: Bool,
        text: String
    ) -> AgoraComposerAction {
        switch phase {
        case .discussing, .concluding:
            return .discussionUtterance(text)
        case .idle, .ended, nil:
            return canStartDiscussion ? .startDiscussion(agenda: text) : .legacyRootSend(text)
        }
    }
}
