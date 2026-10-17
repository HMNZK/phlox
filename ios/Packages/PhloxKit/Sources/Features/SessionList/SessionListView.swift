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
                skeletonList
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
        VStack(spacing: DSSpacing.l) {
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
        ZStack(alignment: .top) {
            skeletonList
                .opacity(0.4)
                .accessibilityHidden(true)
            UnreachableView(viewModel: unreachableViewModel)
                .padding(.top, DSSpacing.s)
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
                    .frame(minWidth: 26, minHeight: 26)
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
                .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
                    .accessibilityLabel(SessionListAccessibility.addSession(projectName: group.title))
                }
            }

            if isExpanded {
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
                    .font(DSFont.caption.weight(entry.state == .doneUnread ? .medium : (presentation.weight?.fontWeight ?? .regular)))
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
            reduceMotion: reduceMotion,
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
            reduceMotion: reduceMotion,
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            if expandedGroupIDs.contains(id) { expandedGroupIDs.remove(id) }
            else { expandedGroupIDs.insert(id) }
        }
    }

    private func toggleSession(_ id: String) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            if expandedSessionIDs.contains(id) { expandedSessionIDs.remove(id) }
            else { expandedSessionIDs.insert(id) }
        }
    }

    private var skeletonList: some View {
        VStack(alignment: .leading, spacing: SessionListMetrics.skeletonSectionSpacing) {
            skeletonSection(headingWidth: 90, rowWidths: [0.58, 0.4])
            skeletonSection(headingWidth: 120, rowWidths: [0.66, 0.44, 0.52, 0.38])
            skeletonSection(headingWidth: 80, rowWidths: [0.48, 0.6])
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
    let reduceMotion: Bool
    let onToggle: (String) -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                SessionListTreeRow(
                    node: node,
                    depth: depth,
                    expandedSessionIDs: expandedSessionIDs,
                    reduceMotion: reduceMotion,
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
    let reduceMotion: Bool
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

            if isExpanded, !node.children.isEmpty {
                SessionListTreeRows(
                    nodes: node.children,
                    depth: depth + 1,
                    expandedSessionIDs: expandedSessionIDs,
                    reduceMotion: reduceMotion,
                    onToggle: onToggle,
                    onSelect: onSelect
                )
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
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    onToggle(node.id)
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(DSFont.caption.weight(.semibold))
                    .foregroundStyle(IOSColor.text.secondary)
                    .frame(width: SessionListMetrics.controlWidth, height: SessionListMetrics.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                SessionListRunningName(
                    name: presentation.name,
                    suffix: node.collapsedChildCountLabel(isExpanded: isExpanded),
                    state: presentation.state,
                    tone: presentation.nameTone,
                    isSemibold: presentation.isSemibold
                )
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(isAttentionRow ? AccessibilityID.attentionRow(node.id) : AccessibilityID.sessionRow(node.id))
    }
}

private struct SessionListRunningName: View {
    let name: String
    let suffix: String?
    let state: SessionDisplayState
    let tone: SessionListNameTone
    let isSemibold: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didSweep = false

    private var font: Font { DSFont.body.weight(isSemibold ? .semibold : .regular) }
    private var color: Color { tone == .primary ? IOSColor.text.primary : IOSColor.text.secondary }
    private var nameText: Text {
        Text(name).font(font).foregroundColor(color)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            nameText
                .fixedSize(horizontal: false, vertical: true)
            if let suffix {
                Text(suffix)
                    .font(DSFont.footnote.weight(.semibold))
                    .foregroundStyle(IOSColor.text.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            if state == .running && !reduceMotion {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, IOSColor.listRunningGlow.opacity(0.9), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(20, geometry.size.width * 0.35))
                    .offset(x: didSweep ? geometry.size.width : -geometry.size.width)
                    .mask {
                        Text(name)
                            .font(font)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .allowsHitTesting(false)
                }
                .onAppear {
                    guard !didSweep else { return }
                    withAnimation(.linear(duration: 3.2)) { didSweep = true }
                }
                .accessibilityHidden(true)
            }
        }
    }
}

private struct SessionListErrorCard: View {
    let error: PhloxError
    let onRetry: () -> Void
    let onQRScan: () -> Void

    private var title: String {
        switch error {
        case .unauthorized: "Mac に接続を断られました"
        case .server(let status, _) where status >= 500: "Mac の Phlox でエラーが起きました"
        default: error.presentation.title
        }
    }

    private var message: String {
        switch error {
        case .unauthorized:
            "この iPhone に保存した接続の鍵（トークン）が、Mac 側で使えなくなっています。Mac で QR を表示し、読み取り直してください。"
        case .server(let status, _) where status >= 500:
            "要求を処理している途中で、Mac 側で問題が起きました。少し待って再試行してください。続くときは Mac の Phlox を再起動してください。"
        default: error.presentation.message
        }
    }

    private var actionTitle: String {
        if case .unauthorized = error { return "QR で再接続" }
        return error.presentation.recoveryAction ?? "再試行"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text(title)
                .font(DSFont.title.weight(.bold))
                .foregroundStyle(IOSColor.status.error)
            Text(message)
                .font(DSFont.subheadline)
                .foregroundStyle(IOSColor.text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: {
                if case .unauthorized = error { onQRScan() }
                else { onRetry() }
            }) {
                Text(actionTitle)
                    .font(DSFont.headline)
                    .foregroundStyle(IOSColor.accentOnFill)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(IOSColor.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
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
    static let attentionTopSpacing: CGFloat = 4
    static let projectTopSpacing: CGFloat = 14
    static let skeletonSectionSpacing: CGFloat = 14
    static let skeletonHeadingGap: CGFloat = 10
    static let skeletonTopPadding: CGFloat = 26
    static let skeletonLeadingIndent: CGFloat = 36
    static let cardCornerRadius: CGFloat = 22
    static let judgingTopPadding: CGFloat = 144
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
