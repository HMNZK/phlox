import Foundation

/// SubAgentDrawerView の表示述語（subagent-view-parity run / task-2 の契約面）。
/// シグネチャは PM が凍結（受け入れテスト AcceptanceSubAgentDrawerParityTests が符号化）。
/// 本体実装は task-2。View はこの述語を経由して Thinking インジケータ・
/// ツールコール実行中表示を決める（メイン ChatTranscriptView と同じ意味論）。
enum SubAgentDrawerPresentation {
    /// Thinking インジケータを表示するか（メインの showsProcessingIndicator 相当）。
    static func showsThinkingIndicator(status: SubAgentStatus) -> Bool {
        status == .running
    }

    /// item をツールコール実行中（ローディング）として描画するか
    /// （メイン ChatTranscriptView.isRunningCommand と同じ意味論）。
    static func isRunningCommand(item: ChatItem, lastItemID: String?, status: SubAgentStatus) -> Bool {
        guard status == .running else { return false }
        guard case .commandExecution = item else { return false }
        return item.id == lastItemID
    }

    /// Thinking インジケータに添える最新 reasoning のプレビュー
    /// （メイン ChatSessionViewModel.runningReasoningPreview 相当）。
    static func reasoningPreview(transcript: [ChatItem], status: SubAgentStatus) -> String? {
        guard status == .running else { return nil }

        var latestReasoningText: String?
        for item in transcript {
            if case .reasoning(_, let text, _) = item {
                latestReasoningText = text
            }
        }
        guard let latestReasoningText else { return nil }

        let preview = ReasoningPreview.tail(latestReasoningText, maxLines: 3)
        return preview.isEmpty ? nil : preview
    }
}
