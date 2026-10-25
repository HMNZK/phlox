import DesignSystem
import DesignSystemIOS
import PhloxCore
import SwiftUI

/// セッション一覧。
public struct SessionListView: View {
    public static let listTitle = "セッション"

    @Bindable var viewModel: SessionListViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.usageViewModel) private var usageViewModel
    @ScaledMetric(relativeTo: .subheadline) private var attentionCountDiameter: CGFloat = 26
    @State private var isScrolledPastTitle = false
    @State private var expandedGroupIDs: Set<String>
    @State private var expandedSessionIDs: Set<String>
    @State private var didApplyInitialGroupExpansion = false

    private let initialExpandedGroupIDs: Set<String>?
    private let scrollToTopRequest: Int
    let reachability: Reachability
    let endpoint: String
    let onSelectDetail: (String) -> Void
    let onAddSession: (SessionComposeDraft) -> Void
    let onReconnect: () async -> Void
    let onQRScan: () -> Void

    public init(
        viewModel: SessionListViewModel,
        reachability: Reachability = .unknown,
        endpoint: String? = nil,
        onSelectDetail: @escaping (String) -> Void,
        onAddSession: @escaping (SessionComposeDraft) -> Void,
        onReconnect: @escaping () async -> Void = {},
        onQRScan: @escaping () -> Void = {},
        scrollToTopRequest: Int = 0,
        initialExpandedGroupIDs: Set<String>? = nil,
        initialExpandedSessionIDs: Set<String> = []
    ) {
        self.viewModel = viewModel
        self.reachability = reachability
        self.endpoint = endpoint ?? viewModel.connectionEndpoint
        self.onSelectDetail = onSelectDetail
        self.onAddSession = onAddSession
        self.onReconnect = onReconnect
        self.onQRScan = onQRScan
        self.scrollToTopRequest = scrollToTopRequest
        self.initialExpandedGroupIDs = initialExpandedGroupIDs
        _expandedGroupIDs = State(initialValue: initialExpandedGroupIDs ?? [])
        _expandedSessionIDs = State(initialValue: initialExpandedSessionIDs)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleHeader
                            .id("session-list-top")
                            .padding(.bottom, SessionListMetrics.titleBottomSpacing)

                        pageContent(minimumHeight: max(0, geometry.size.height - 80))
                    }
                    .padding(.horizontal, SessionListMetrics.horizontalPadding)
                    .padding(.bottom, DSSpacing.l)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    // 非同期の取得・削除結果が実際に届いた時点の行配置へ適用する。
                    .animation(reduceMotion ? nil : DSMotion.rowRemoval, value: viewModel.lastKnownSessions.map(\.id))
                }
                .background(IOSColor.bg.base)
                .refreshable {
                    await SessionPullRefresh.perform(
                        sessionList: viewModel,
                        usage: usageViewModel
                    )
                }
                .modifier(
                    ScrolledPastTitleReporter(
                        threshold: SessionListMetrics.titleCollapseThreshold,
                        isScrolledPast: $isScrolledPastTitle
                    )
                )
                .onChange(of: scrollToTopRequest) { _, _ in
                    if reduceMotion {
                        proxy.scrollTo("session-list-top", anchor: .top)
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo("session-list-top", anchor: .top)
                        }
                    }
                }
                .onChange(of: viewModel.projection.projectGroups.map(\.id) + otherGroupIDs, initial: true) { _, ids in
                    if !didApplyInitialGroupExpansion {
                        expandedGroupIDs = initialExpandedGroupIDs ?? Set(ids)
                        didApplyInitialGroupExpansion = true
                    } else if initialExpandedGroupIDs == nil {
                        expandedGroupIDs.formUnion(ids)
                    }
                }
            }
        }
        .background(IOSColor.bg.base)
        .navigationTitle(Self.listTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isScrolledPastTitle ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if isScrolledPastTitle {
                    Text(Self.listTitle)
                        .font(DSFont.headline)
                        .foregroundStyle(IOSColor.text.primary)
                }
            }
        }
        #endif
        .task {
            guard !isUITesting else { return }
            viewModel.start()
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isUITesting else { return }
            if phase == .active { viewModel.start() } else { viewModel.stop() }
        }
        .accessibilityIdentifier(AccessibilityID.sessionList)
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
            || ProcessInfo.processInfo.environment["PHLOX_DESIGN_SNAPSHOTS"] == "1"
    }

    private var otherGroupIDs: [String] {
        viewModel.projection.otherGroup.map { [$0.id] } ?? []
    }

    private var titleHeader: some View {
        HStack(spacing: 0) {
            Text(Self.listTitle)
                .font(DSFont.largeTitle)
                .foregroundStyle(IOSColor.text.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            DSLegacyNewChatButton {
                onAddSession(SessionComposeDraft(project: ""))
            }
        }
        .padding(.top, SessionListMetrics.titleTopPadding)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func pageContent(minimumHeight: CGFloat) -> some View {
        switch viewModel.state {
        case .loading:
            if reachability == .unknown {
                judgingView(minimumHeight: minimumHeight)
            } else {
                skeletonList()
            }
        case .empty:
            EmptyStateView {
                onAddSession(SessionComposeDraft(project: ""))
            }
            .frame(minHeight: minimumHeight, alignment: .top)
        case .offline:
            offlineContent(minimumHeight: minimumHeight)
        case .error(let error):
            SessionListErrorCard(error: error, onRetry: {
                Task { await viewModel.refresh() }
            }, onQRScan: onQRScan)
            .frame(minHeight: minimumHeight, alignment: .top)
            .padding(.top, DSSpacing.s)
        case .loaded:
            loadedSections
        }
    }

    private func judgingView(minimumHeight: CGFloat) -> some View {
        VStack(spacing: DSSpacing.m) {
            ProgressView()
                .controlSize(.large)
                .tint(IOSColor.text.tertiary)
                .accessibilityHidden(true)
            Text("Mac に接続しています…")
                .font(DSFont.title2)
                .foregroundStyle(IOSColor.text.primary)
            Text(endpoint)
                .font(DSFont.campMonoCaption)
                .foregroundStyle(IOSColor.text.secondary)
                .textSelection(.disabled)
        }
        .padding(.top, SessionListMetrics.judgingTopPadding)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    private func offlineContent(minimumHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            UnreachableView(viewModel: unreachableViewModel)
                .padding(.top, DSSpacing.s)
            skeletonList(isOffline: true)
                .opacity(0.4)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .top)
    }

    private var unreachableViewModel: UnreachableViewModel {
        UnreachableViewModel(
            reachability: reachability,
            endpoint: endpoint,
            lastUpdated: viewModel.lastFetchedAt,
            onRetry: {
                await onReconnect()
                await viewModel.refresh()
            }
        )
    }

    private var loadedSections: some View {
        VStack(alignment: .leading, spacing: SessionListMetrics.sectionSpacing) {
            if !viewModel.projection.attentionSessions.isEmpty {
                attentionSection
            }

            ForEach(viewModel.projection.projectGroups) { group in
                projectSection(group)
            }

            if let group = viewModel.projection.otherGroup {
                projectSection(group)
            }
        }
        .padding(.top, viewModel.projection.attentionSessions.isEmpty
            ? SessionListMetrics.projectTopSpacing
            : SessionListMetrics.attentionTopSpacing)
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            HStack(spacing: DSSpacing.s) {
                Text("対応待ち")
                    .font(DSFont.title)
                    .foregroundStyle(IOSColor.text.primary)
                Text("\(viewModel.projection.attentionSessions.count)")
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(IOSColor.text.primary)
                    .frame(minWidth: attentionCountDiameter, minHeight: attentionCountDiameter)
                    .background(IOSColor.bg.raised, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.leading, DSSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("対応待ち、\(viewModel.projection.attentionSessions.count) 件")
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(viewModel.projection.attentionSessions.enumerated()), id: \.element.id) { index, session in
                    attentionRow(session)
                    if index < viewModel.projection.attentionSessions.count - 1 {
                        rowDivider(leadingIndent: SessionListMetrics.controlWidth)
                    }
                }
            }
            .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: SessionListMetrics.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SessionListMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(IOSColor.bg.separator, lineWidth: 1)
            }
        }
    }

    private func projectSection(_ group: ProjectGroup) -> some View {
        let isExpanded = expandedGroupIDs.contains(group.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    toggleGroup(group.id)
                } label: {
                    HStack(spacing: DSSpacing.s) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(DSFont.caption.weight(.semibold))
                            .foregroundStyle(IOSColor.text.secondary)
                            .frame(width: 14)
                            .accessibilityHidden(true)
                        Text(group.title)
                            .font(DSFont.title)
                            .foregroundStyle(IOSColor.text.primary)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        if !isExpanded, !group.collapsedSummary.entries.isEmpty {
                            collapsedSummary(group.collapsedSummary)
                                .padding(.leading, DSSpacing.xs)
                        }
                    }
                    .padding(.horizontal, DSSpacing.xs)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSPressFeedbackStyle())
                .accessibilityLabel(
                    SessionListAccessibility.projectHeader(
                        name: group.title,
                        count: group.sessionCount,
                        isExpanded: isExpanded
                    )
                )
                .accessibilityAddTraits(.isHeader)

                if !group.isOther {
                    Button {
                        onAddSession(group.addSessionDraft)
                    } label: {
                        Image(systemName: "plus")
                            .font(DSFont.title)
                            .foregroundStyle(IOSColor.text.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressFeedbackStyle())
                    .accessibilityLabel(SessionListAccessibility.addSession(projectName: group.title))
                }
            }

            DSDisclosureContent(isExpanded: isExpanded) {
                VStack(spacing: 0) {
                    treeRows(group.roots, depth: 0)
                }
                .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: SessionListMetrics.cardCornerRadius, style: .continuous))
            }
        }
    }

    private func collapsedSummary(_ summary: SessionListCollapsedSummary) -> some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(summary.entries) { entry in
                let presentation = IOSStatusVocabulary.presentation(for: entry.state, locale: Locale(identifier: "ja_JP"))
                Text(entry.label)
                    .font(DSFont.iosCaption2.weight(entry.state == .doneUnread ? .medium : (presentation.weight?.fontWeight ?? .regular)))
                    .foregroundStyle(entry.state == .doneUnread ? IOSColor.text.secondary : (presentation.color ?? IOSColor.text.tertiary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityHidden(true)
            }
        }
    }

    private func treeRows(_ nodes: [SessionListTreeNode], depth: Int) -> some View {
        SessionListTreeRows(
            nodes: nodes,
            depth: depth,
            expandedSessionIDs: expandedSessionIDs,
            onToggle: toggleSession,
            onSelect: onSelectDetail
        )
    }

    private func attentionRow(_ session: Session) -> some View {
        let node = SessionListTreeNode(session: session, children: [])
        return SessionListTreeRow(
            node: node,
            depth: 0,
            expandedSessionIDs: [],
            isAttentionRow: true,
            onToggle: { _ in },
            onSelect: onSelectDetail
        )
    }

    private func rowDivider(leadingIndent: CGFloat) -> some View {
        Rectangle()
            .fill(IOSColor.bg.separator)
            .frame(height: 1)
            .padding(.leading, leadingIndent)
    }

    private func toggleGroup(_ id: String) {
        if expandedGroupIDs.contains(id) { expandedGroupIDs.remove(id) }
        else { expandedGroupIDs.insert(id) }
    }

    private func toggleSession(_ id: String) {
        if expandedSessionIDs.contains(id) { expandedSessionIDs.remove(id) }
        else { expandedSessionIDs.insert(id) }
    }

    private func skeletonList(isOffline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: SessionListMetrics.skeletonSectionSpacing) {
            skeletonSection(headingWidth: 90, rowWidths: [0.58, 0.4])
            skeletonSection(headingWidth: 120, rowWidths: [0.66, 0.44, 0.52, 0.38])
            if !isOffline {
                skeletonSection(headingWidth: 80, rowWidths: [0.48, 0.6])
            }
        }
        .padding(.top, SessionListMetrics.skeletonTopPadding)
        .accessibilityHidden(true)
    }

    private func skeletonSection(headingWidth: CGFloat, rowWidths: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: SessionListMetrics.skeletonHeadingGap) {
            RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                .fill(IOSColor.bg.raised)
                .frame(width: headingWidth, height: 16)
                .padding(.horizontal, DSSpacing.xs)
            VStack(spacing: 0) {
                ForEach(Array(rowWidths.enumerated()), id: \.offset) { index, width in
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                                .fill(IOSColor.bg.raised.opacity(0.72))
                                .frame(
                                    width: max(0, geometry.size.width - SessionListMetrics.skeletonLeadingIndent - DSSpacing.l)
                                        * width,
                                    height: 13
                                )
                                .offset(x: SessionListMetrics.skeletonLeadingIndent)
                            RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                                .fill(IOSColor.bg.raised.opacity(0.72))
                                .frame(width: 52, height: 11)
                                .offset(x: geometry.size.width - DSSpacing.l - 52)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: 48)
                    if index < rowWidths.count - 1 {
                        rowDivider(leadingIndent: 0)
                    }
                }
            }
            .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: SessionListMetrics.cardCornerRadius, style: .continuous))
        }
    }

}

private struct SessionListTreeRows: View {
    let nodes: [SessionListTreeNode]
    let depth: Int
    let expandedSessionIDs: Set<String>
    let onToggle: (String) -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                SessionListTreeRow(
                    node: node,
                    depth: depth,
                    expandedSessionIDs: expandedSessionIDs,
                    showsSiblingDivider: index < nodes.count - 1,
                    onToggle: onToggle,
                    onSelect: onSelect
                )
            }
        }
    }
}

private struct SessionListTreeRow: View {
    let node: SessionListTreeNode
    let depth: Int
    let expandedSessionIDs: Set<String>
    var showsSiblingDivider = false
    var isAttentionRow = false
    let onToggle: (String) -> Void
    let onSelect: (String) -> Void

    private var isExpanded: Bool { expandedSessionIDs.contains(node.id) }
    private var presentation: SessionListRowPresentation {
        SessionListRowPresentation(session: node.session, depth: depth)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(IOSColor.bg.separator)
                        .frame(width: 1.5)
                        .frame(minWidth: SessionListMetrics.childIndent, maxWidth: SessionListMetrics.childIndent, maxHeight: .infinity, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                leadingControl
                rowButton
            }
            .frame(minHeight: SessionListMetrics.rowHeight)

            if showsSiblingDivider {
                Rectangle()
                    .fill(IOSColor.bg.separator)
                    .frame(height: 1)
                    .padding(.leading, SessionListMetrics.controlWidth + CGFloat(depth) * SessionListMetrics.childIndent)
            }

            if !node.children.isEmpty {
                DSDisclosureContent(isExpanded: isExpanded) {
                    SessionListTreeRows(
                        nodes: node.children,
                        depth: depth + 1,
                        expandedSessionIDs: expandedSessionIDs,
                        onToggle: onToggle,
                        onSelect: onSelect
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        if isAttentionRow || node.children.isEmpty {
            // 子の開閉印を持たない行も44ptの欄を保ち、20ptの空白をその中央に置く。
            Color.clear
                .frame(width: SessionListMetrics.leafIndent, height: SessionListMetrics.rowHeight)
                .frame(
                    width: SessionListMetrics.controlWidth,
                    height: SessionListMetrics.rowHeight
                )
                .accessibilityHidden(true)
        } else {
            Button {
                onToggle(node.id)
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(DSFont.caption.weight(.semibold))
                    .foregroundStyle(IOSColor.text.secondary)
                    .frame(width: SessionListMetrics.controlWidth, height: SessionListMetrics.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressFeedbackStyle())
            .accessibilityLabel(
                SessionListAccessibility.childDisclosure(
                    name: node.session.name,
                    count: node.descendantCount,
                    isExpanded: isExpanded
                )
            )
        }
    }

    private var rowButton: some View {
        Button {
            onSelect(node.session.id)
        } label: {
            HStack(spacing: DSSpacing.s) {
                SessionListName(
                    name: presentation.name,
                    suffix: node.collapsedChildCountLabel(isExpanded: isExpanded),
                    tone: presentation.nameTone,
                    isSemibold: presentation.isSemibold
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if presentation.state.showsActivityIndicator {
                    SessionActivityIndicator(state: presentation.state)
                }

                if let stateLabel = presentation.statusLabel {
                    let status = IOSStatusVocabulary.presentation(for: presentation.state, locale: Locale(identifier: "ja_JP"))
                    Text(stateLabel)
                        .font(DSFont.subheadline.weight(status.weight?.fontWeight ?? .regular))
                        .foregroundStyle(status.color ?? IOSColor.text.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.trailing, DSSpacing.m)
            .frame(maxWidth: .infinity, minHeight: SessionListMetrics.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressFeedbackStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(isAttentionRow ? AccessibilityID.attentionRow(node.id) : AccessibilityID.sessionRow(node.id))
    }
}

private struct SessionListName: View {
    let name: String
    let suffix: String?
    let tone: SessionListNameTone
    let isSemibold: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var font: Font { DSFont.body.weight(isSemibold ? .semibold : .regular) }
    private var color: Color { tone == .primary ? IOSColor.text.primary : IOSColor.text.secondary }
    private var nameText: Text {
        Text(name).font(font).foregroundColor(color)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            nameText
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            if let suffix {
                Text(suffix)
                    .font(DSFont.footnote.weight(.semibold))
                    .foregroundStyle(IOSColor.text.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SessionListErrorCard: View {
    let error: PhloxError
    let onRetry: () -> Void
    let onQRScan: () -> Void

    private var presentation: ErrorPresentation { error.presentation }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text(presentation.title)
                .font(DSFont.title.weight(.bold))
                .foregroundStyle(presentation.isNeutral ? IOSColor.text.primary : IOSColor.status.error)
            Text(presentation.cause)
                .font(DSFont.subheadline)
                .lineSpacing(5)
                .foregroundStyle(IOSColor.text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !presentation.nextStep.isEmpty {
                Text(presentation.nextStep)
                    .font(DSFont.subheadline)
                    .lineSpacing(5)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = presentation.technicalDetail {
                Text(detail)
                    .font(DSFont.campMonoCaption)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: {
                if case .unauthorized = error { onQRScan() }
                else { onRetry() }
            }) {
                Text(presentation.recoveryAction ?? "再試行")
                    .font(DSFont.headline)
                    .foregroundStyle(IOSColor.accentOnFill)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(IOSColor.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(DSPressFeedbackStyle())
            .padding(.top, DSSpacing.l)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: SessionListMetrics.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.sessionListError)
    }
}

private enum SessionListMetrics {
    static let horizontalPadding = DSSpacing.l
    static let titleTopPadding: CGFloat = 42
    static let titleBottomSpacing: CGFloat = 10
    static let controlWidth: CGFloat = 44
    static let leafIndent: CGFloat = 20
    static let childIndent: CGFloat = 22
    static let rowHeight: CGFloat = 48
    static let sectionSpacing: CGFloat = 14
    static let attentionTopSpacing: CGFloat = 16
    static let projectTopSpacing: CGFloat = 14
    static let skeletonSectionSpacing: CGFloat = 14
    static let skeletonHeadingGap: CGFloat = 10
    static let skeletonTopPadding: CGFloat = 26
    static let skeletonLeadingIndent: CGFloat = 36
    static let cardCornerRadius: CGFloat = 22
    static let judgingTopPadding: CGFloat = 140
    static let titleCollapseThreshold: CGFloat = 40
}

private struct ScrolledPastTitleReporter: ViewModifier {
    let threshold: CGFloat
    @Binding var isScrolledPast: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > threshold
        } action: { _, newValue in
            if isScrolledPast != newValue { isScrolledPast = newValue }
        }
        #else
        content
        #endif
    }
}
