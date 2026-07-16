import SwiftUI
import AgentDomain
import DesignSystem

/// アゴラ討論中のヘッダ（task-5 契約・AcceptanceAgoraDiscussionUITests が凍結）。
/// 発言カウンタ「n/max」・停止ボタン・参加者チップ（役割名付き）を表示する。
/// セマンティクスの正本は tasks/task-5.md。公開 surface は暫定（PM 承認の上で調整可）。
public struct AgoraDiscussionHeaderView: View {
    /// ヘッダに表示する参加者1名分の表示データ。
    public struct Participant: Equatable, Identifiable {
        public let id: SessionID
        public let displayName: String
        public let role: String?
        public let isFacilitator: Bool

        public init(id: SessionID, displayName: String, role: String?, isFacilitator: Bool) {
            self.id = id
            self.displayName = displayName
            self.role = role
            self.isFacilitator = isFacilitator
        }
    }

    let utteranceCount: Int
    let maxUtterances: Int
    let participants: [Participant]
    let onStop: () -> Void

    public init(
        utteranceCount: Int,
        maxUtterances: Int,
        participants: [Participant],
        onStop: @escaping () -> Void
    ) {
        self.utteranceCount = utteranceCount
        self.maxUtterances = maxUtterances
        self.participants = participants
        self.onStop = onStop
    }

    /// 発言カウンタの表示文字列（「n/max」）。
    var counterText: String {
        "\(utteranceCount)/\(maxUtterances)"
    }

    /// 参加者チップの表示文字列。役割があれば名前と役割の両方を含め、無ければ名前のみ。
    static func chipText(name: String, role: String?) -> String {
        guard let role, !role.isEmpty else { return name }
        return "\(name) · \(role)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            HStack(spacing: DSSpacing.s) {
                Text(counterText)
                    .font(DSFont.captionStrong)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 0)
                Button("停止", action: onStop)
                    .accessibilityIdentifier("agora.stopDiscussion")
                    .font(DSFont.captionStrong)
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(participants) { participant in
                        Text(Self.chipText(name: participant.displayName, role: participant.role))
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textPrimary)
                            .padding(.horizontal, DSSpacing.s)
                            .padding(.vertical, DSSpacing.xs)
                            .background(DSColor.fillSubtle, in: Capsule())
                    }
                }
            }
        }
    }
}
