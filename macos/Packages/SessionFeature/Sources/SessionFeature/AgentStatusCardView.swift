import SwiftUI
import AgentDomain
import DesignSystem

// エージェント状態カード（要件 agent-status-card.md、設計 agent-status-card-design.md §5、ADR 0226・0227）。
// 組み立て（AgentStatusCardBuilder）が作った `AgentStatusCard` を描く。`DisclosureCard` は使わない。
//
// 見本（ClaudeDesign/agent-status-card/boards/10-Anatomy.html「寸法と色」）との対応:
//   面 = DSColor.chatCard、線 = DSColor.separator / border、文字 = chatTextPrimary / chatTextSecondary / textTertiary、
//   アイコン・印 = textTertiary（見本の 50% 半透明に最も近いトークン）、ホバー・開いた行の面 = fillSubtle、
//   角丸 12 = DSRadius.l。そのほかの寸法は下の `AgentStatusCardLayout` に 1 か所で持つ。

enum AgentStatusCardLayout {
    static let headerHeight: CGFloat = 40
    static let headerGap: CGFloat = 10
    /// 見出しの左右の余白。グリッドの狭い列は 10 に詰める（見本 09）。
    static func headerLeading(isNarrow: Bool) -> CGFloat { isNarrow ? 10 : 13 }
    static func headerTrailing(isNarrow: Bool) -> CGFloat { isNarrow ? 10 : 14 }
    /// 見出しの左の印（点描・✓）の枠。
    static let leadSize: CGFloat = 18

    static let taskRowHeight: CGFloat = 28
    static let taskColumnGap: CGFloat = 6
    static let chevronSize: CGFloat = 14
    static let markSize: CGFloat = 18
    /// 縦の線: 印の中心（行の左の余白 2 + シェブロン + 間隔 + 印の半分）の 0.5 左、印の下端から、次の行の頭まで。
    static let connectorX: CGFloat = 2 + chevronSize + taskColumnGap + markSize / 2 - 0.5
    static let connectorTop: CGFloat = taskRowHeight / 2 + 7
    static let connectorOverlap: CGFloat = 7

    static let actionRowHeight: CGFloat = 24
    static let actionIconSize: CGFloat = 16
    /// 作業の行の字下げ。グリッドの狭い列は 36。
    static func actionIndent(isNarrow: Bool) -> CGFloat { isNarrow ? 36 : 40 }
    /// 文章・開いた中身の字下げ（作業の行の文字の位置）。
    static let textIndent: CGFloat = 28

    static func bodyPadding(isNarrow: Bool) -> EdgeInsets {
        EdgeInsets(top: 6, leading: 10, bottom: 10, trailing: isNarrow ? 10 : 12)
    }
}

struct AgentStatusCardView: View, Equatable {
    let card: AgentStatusCard
    let agentDescriptor: AgentDescriptor
    /// 圧縮中・接続待ちの間は、点描を止めて静止表示にする（動くものを 2 つ重ねない）。
    var isStill = false
    /// グリッドの狭い列。作業の行の字下げが 36 になり、進行中の小さい点描は止める。
    var isNarrow = false
    var isLaunchFailureRestarting = false

    // 以下は比較に含めない（毎回作り直されるクロージャ。ADR 0116）。
    /// 無応答の判定。時刻で変わるので、見出しが毎秒この関数から決める。
    var hangAssessment: ((Date) -> ChatHangAssessment?)? = nil
    var onInterrupt: (() async -> Void)? = nil
    /// 文章・思考以外の item（回答済みの質問・エラー）の描画。
    var makeItemView: ((ChatItem) -> ChatItemView)? = nil

    @State private var disclosure: AgentStatusCardDisclosure
    /// 最初から開いている作業の行（画面外の描画で「作業を開いた」状態を作るために使う）。
    private let openActionIDs: Set<String>
    @State private var isInViewHierarchy = false
    @State private var isInViewport = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    init(
        card: AgentStatusCard,
        agentDescriptor: AgentDescriptor,
        isStill: Bool = false,
        isNarrow: Bool = false,
        isLaunchFailureRestarting: Bool = false,
        hangAssessment: ((Date) -> ChatHangAssessment?)? = nil,
        onInterrupt: (() async -> Void)? = nil,
        makeItemView: ((ChatItem) -> ChatItemView)? = nil,
        disclosure: AgentStatusCardDisclosure = AgentStatusCardDisclosure(),
        openActionIDs: Set<String> = []
    ) {
        self.card = card
        self.agentDescriptor = agentDescriptor
        self.isStill = isStill
        self.isNarrow = isNarrow
        self.isLaunchFailureRestarting = isLaunchFailureRestarting
        self.hangAssessment = hangAssessment
        self.onInterrupt = onInterrupt
        self.makeItemView = makeItemView
        _disclosure = State(initialValue: disclosure)
        self.openActionIDs = openActionIDs
    }

    /// 実行中でないカードは時刻が進んでも等しい（時刻は表示の時計だけが持つ）。
    nonisolated static func == (lhs: AgentStatusCardView, rhs: AgentStatusCardView) -> Bool {
        lhs.card == rhs.card
            && lhs.agentDescriptor == rhs.agentDescriptor
            && lhs.isStill == rhs.isStill
            && lhs.isNarrow == rhs.isNarrow
            && lhs.isLaunchFailureRestarting == rhs.isLaunchFailureRestarting
    }

    /// 既存の処理中表示と同じ条件（表示されていて、画面内にあり、バックグラウンドでない）。
    private var isTimelineVisible: Bool {
        ThinkingAnimationModel.isTimelineVisible(
            isInViewHierarchy: isInViewHierarchy,
            isInTranscriptViewport: isInViewport,
            scenePhase: scenePhase
        )
    }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let itemView = makeItemView ?? { item in
            ChatItemView(item: item, isRunningCommand: false, agentDescriptor: agentDescriptor)
        }
        VStack(alignment: .leading, spacing: 0) {
            AgentStatusHeaderView(
                header: card.header,
                scale: scale,
                isAnimating: isTimelineVisible && !isStill,
                isTimelineVisible: isTimelineVisible,
                isNarrow: isNarrow,
                hangAssessment: hangAssessment,
                onInterrupt: onInterrupt
            )
            if !card.rows.isEmpty {
                Rectangle().fill(DSColor.separator).frame(height: 1)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(card.rows.enumerated()), id: \.element.id) { index, row in
                        AgentStatusTaskRow(
                            row: row,
                            isLast: index == card.rows.count - 1,
                            isExpanded: disclosure.isExpanded(row, in: card),
                            isManuallyOpened: disclosure.isManuallyOpened(row, in: card),
                            entryLimit: disclosure.entryLimit(row, in: card),
                            scale: scale,
                            isNarrow: isNarrow,
                            isAnimating: isTimelineVisible && !isStill && !isNarrow,
                            isTimelineVisible: isTimelineVisible,
                            openActionIDs: openActionIDs,
                            makeItemView: itemView,
                            onToggle: { disclosure.toggle(row, in: card) },
                            onShowMore: { disclosure.showMore(row, in: card) }
                        )
                    }
                }
                .padding(AgentStatusCardLayout.bodyPadding(isNarrow: isNarrow))
            }
        }
        .background(DSColor.chatCard, in: RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .strokeBorder(DSColor.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("AgentStatusCard")
        .onAppear { isInViewHierarchy = true }
        .onDisappear { isInViewHierarchy = false }
        .onViewportVisibilityChange { isInViewport = $0 }
    }
}
