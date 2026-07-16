import AgentDomain
import SessionFeature

// task-4 契約の PM スタブ。API 表面は受け入れテスト
// AcceptanceAgoraTimelineDisplayTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-4.md

/// アゴラ討論タイムラインの表示内容ポリシー（純関数）。
/// 討論の観戦には「発言（結果）」だけを見せ、生成過程（reasoning・ツール実行）は出さない。
public enum AgoraTimelineContentPolicy {
    /// このタイムラインに表示する ChatItem か。
    /// userMessage / agentMessage / error のみ true。
    public static func includes(_ item: ChatItem) -> Bool {
        switch item {
        case .userMessage, .agentMessage, .error:
            return true
        case .reasoning, .commandExecution, .fileChange, .subAgentMarker, .turnCost:
            return false
        }
    }

    /// appServer transcript からタイムラインへ流す項目だけを残す。
    public static func filteredTranscript(_ items: [ChatItem]) -> [ChatItem] {
        items.filter(includes)
    }
}

/// アゴラの参加者生成中インジケータ表示ポリシー（純関数）。
public enum AgoraThinkingPolicy {
    /// このセッション状態のときに Thinking インジケータを表示するか（running のみ true）。
    public static func showsThinking(status: SessionStatus) -> Bool {
        if case .running = status { return true }
        return false
    }

    /// タイムライン末尾に Thinking 行を出す参加者の session ID（sources の表示順を維持）。
    public static func thinkingSessionIDs(
        sources: [TeamTimelineSource],
        statusesByID: [SessionID: SessionStatus]
    ) -> [SessionID] {
        sources.compactMap { source in
            guard let status = statusesByID[source.id],
                  showsThinking(status: status) else { return nil }
            return source.id
        }
    }
}
