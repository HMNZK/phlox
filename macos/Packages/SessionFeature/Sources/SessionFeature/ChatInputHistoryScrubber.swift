import SwiftUI
import DesignSystem

/// スクラバーの横線とパネルの行は共有の「選択位置」で連動し、選択中の入力を
/// 両方で強調する。線・行のいずれをクリックしてもその入力へジャンプする。
struct ChatInputHistoryScrubber: View {
    let entries: [InputHistoryEntry]
    /// スクロール位置に連動する「現在読んでいる入力」。ホバー中でなければこれを強調する。
    let currentPositionID: String?
    let onJump: (String) -> Void
    var hasEarlier = false
    var isLoading = false
    var loadError: String?
    var onLoadEarlier: (() -> Void)?
    var onRetry: (() -> Void)?
    var latestEntries: [InputHistoryEntry]?
    var hasNewer = false
    var onLoadNewer: (() -> Void)?

    private static let tickCap = 12
    private static let panelWidth: CGFloat = 320
    private static let panelMaxHeight: CGFloat = 320
    private static let closeDelay: Duration = .milliseconds(200)
    /// 細い横線を掴みやすくするための、不可視のクリック／ホバー領域。
    private static let tickHitWidth: CGFloat = DSSpacing.xl
    private static let tickHitHeight: CGFloat = DSSpacing.m

    @State private var isPanelPresented: Bool
    @State private var hoveringScrubber = false
    @State private var hoveringPanel = false
    /// ホバー中の入力 id。未ホバーなら最新入力を選択位置とみなす。
    @State private var activeID: String? = nil
    @State private var closeTask: Task<Void, Never>? = nil
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    init(
        entries: [InputHistoryEntry],
        currentPositionID: String? = nil,
        onJump: @escaping (String) -> Void,
        initiallyExpanded: Bool = false,
        hasEarlier: Bool = false,
        isLoading: Bool = false,
        loadError: String? = nil,
        onLoadEarlier: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        latestEntries: [InputHistoryEntry]? = nil,
        hasNewer: Bool = false,
        onLoadNewer: (() -> Void)? = nil
    ) {
        self.entries = entries
        self.currentPositionID = currentPositionID
        self.onJump = onJump
        self.hasEarlier = hasEarlier
        self.isLoading = isLoading
        self.loadError = loadError
        self.onLoadEarlier = onLoadEarlier
        self.onRetry = onRetry
        self.latestEntries = latestEntries
        self.hasNewer = hasNewer
        self.onLoadNewer = onLoadNewer
        _isPanelPresented = State(initialValue: initiallyExpanded)
    }

    /// スクラバーとパネルで共有する選択位置。ホバー中はその id、
    /// 非ホバー時はスクロール連動の現在位置、無ければ最新入力。
    private var selectedID: String? { activeID ?? currentPositionID ?? latestEntries?.last?.id ?? entries.last?.id }

    var body: some View {
        let _ = themeID
        // 戻る先が複数あるときだけ出す。入力欄の右上に縦の目盛り 12 本（PhloxReply.dc.html の ticks）。
        // 履歴のパネルは目盛りの上に開く。
        if (latestEntries ?? entries).count > 1 || entries.count > 1 || isLoading || loadError != nil || hasEarlier || hasNewer {
            scrubber
                .overlay(alignment: .topTrailing) {
                    if isPanelPresented {
                        historyPanel
                            .onHover(perform: setPanelHover)
                            .placedAbove(gap: DSSpacing.xs)
                            .transition(.opacity)
                    }
                }
                .onHover(perform: setScrubberHover)
                .animation(.easeOut(duration: 0.12), value: isPanelPresented)
                .onDisappear(perform: cancelPendingClose)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("入力履歴")
                .accessibilityIdentifier("ChatInputHistoryScrubber")
                .accessibilityAction { isPanelPresented.toggle() }
                .accessibilityAction(named: Text("入力履歴を表示")) { isPanelPresented = true }
                .help("ポインタを置くと入力履歴を表示")
        }
    }

    /// 下揃えの縦の目盛り。今読んでいる入力をアクセントで高く、他は弱い文字色 45%（高さ 6/8/10 の繰り返し）。
    /// 各目盛りは幅 6 のヒット領域を持ち、ホバーで選択、クリックでジャンプする。
    private var scrubber: some View {
        let ticks = InputHistoryPolicy.scrubberTicks(from: latestEntries ?? entries, cap: Self.tickCap)
        let selected = selectedID
        return HStack(alignment: .bottom, spacing: 0) {
            if ticks.isEmpty {
                Button { isPanelPresented.toggle() } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(DSFont.meta)
                        .foregroundStyle(DSColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("入力履歴")
            }
            ForEach(Array(ticks.enumerated()), id: \.element.id) { offset, tick in
                let isSelected = tick.id == selected
                Button {
                    jump(to: tick.id)
                } label: {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(isSelected ? DSColor.accent : DSColor.textTertiary)
                        .frame(width: 3, height: isSelected ? 12 : 6 + CGFloat(offset % 3) * 2)
                        .opacity(isSelected ? 1 : (hoveringScrubber ? 0.7 : 0.45))
                        .frame(width: 6, height: 12, alignment: .bottom)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { activeID = tick.id } }
                .accessibilityLabel(Text(verbatim: tick.text))
                .accessibilityIdentifier("ChatInputHistoryScrubber.tick")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4.5)
        .background(DSColor.chatBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: selected)
        .animation(.easeOut(duration: 0.12), value: hoveringScrubber)
    }

    private var historyPanel: some View {
        let selected = selectedID
        return ScrollView {
            LazyVStack(spacing: DSSpacing.xxs) {
                if hasEarlier {
                    Button("以前の入力を読み込む") { onLoadEarlier?() }
                        .disabled(isLoading)
                        .accessibilityIdentifier("ChatInputHistoryScrubber.loadEarlier")
                }
                if isLoading { ProgressView().controlSize(.small) }
                if let loadError {
                    Text(loadError).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                    Button("再試行") { onRetry?() }
                }

                ForEach(entries) { entry in
                    ChatInputHistoryRow(
                        entry: entry,
                        isSelected: entry.id == selected,
                        onHover: { activeID = entry.id },
                        onJump: jump
                    )
                }
                if hasNewer {
                    Button("以後の入力を読み込む") { onLoadNewer?() }
                        .disabled(isLoading)
                        .accessibilityIdentifier("ChatInputHistoryScrubber.loadNewer")
                }
            }
            .padding(DSSpacing.s)
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: Self.panelMaxHeight)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.attention, style: .continuous))
        .dsPopupSurface()
        .animation(.easeOut(duration: 0.12), value: selected)
        .accessibilityIdentifier("ChatInputHistoryScrubber.panel")
    }

    private func setScrubberHover(_ isHovering: Bool) {
        hoveringScrubber = isHovering
        syncPresentation()
    }

    private func setPanelHover(_ isHovering: Bool) {
        hoveringPanel = isHovering
        syncPresentation()
    }

    /// スクラバー／パネルのどちらかにポインタがあれば開き、両方から外れたら猶予付きで閉じる。
    private func syncPresentation() {
        if hoveringScrubber || hoveringPanel {
            cancelPendingClose()
            isPanelPresented = true
        } else {
            scheduleClose()
        }
    }

    private func scheduleClose() {
        cancelPendingClose()
        closeTask = Task { @MainActor in
            do {
                try await Task.sleep(for: Self.closeDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            isPanelPresented = false
            activeID = nil
            closeTask = nil
        }
    }

    private func cancelPendingClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func jump(to entryID: String) {
        cancelPendingClose()
        hoveringScrubber = false
        hoveringPanel = false
        isPanelPresented = false
        activeID = nil
        onJump(entryID)
    }
}

private struct ChatInputHistoryRow: View {
    let entry: InputHistoryEntry
    let isSelected: Bool
    let onHover: () -> Void
    let onJump: (String) -> Void

    var body: some View {
        Button {
            onJump(entry.id)
        } label: {
            Text(entry.text)
                .font(DSFont.body)
                .foregroundStyle(DSColor.chatTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .dsPopupRowHighlight(isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { onHover() } }
        .accessibilityIdentifier("ChatInputHistoryScrubber.row")
    }
}

#if DEBUG
#Preview("スクラバー＋履歴パネル") {
    ChatInputHistoryScrubber(
        entries: (1...8).map {
            InputHistoryEntry(
                id: "u\($0)",
                text: "過去の入力メッセージ \($0)：デザインの相談やコードの依頼など長めの本文サンプル"
            )
        },
        onJump: { _ in },
        initiallyExpanded: true
    )
    .padding(40)
    .frame(width: 520, height: 480)
    .background(DSColor.chatBackground)
}
#endif
