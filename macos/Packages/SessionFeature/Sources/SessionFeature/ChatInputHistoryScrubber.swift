import SwiftUI
import DesignSystem

/// チャットの過去入力へ素早く移動するための、左端の入力履歴スクラバー。
/// スクラバーの横線とパネルの行は共有の「選択位置」で連動し、選択中の入力を
/// 両方で強調する。線・行のいずれをクリックしてもその入力へジャンプする。
struct ChatInputHistoryScrubber: View {
    let entries: [InputHistoryEntry]
    /// スクロール位置に連動する「現在読んでいる入力」。ホバー中でなければこれを強調する。
    let currentPositionID: String?
    let onJump: (String) -> Void

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
        initiallyExpanded: Bool = false
    ) {
        self.entries = entries
        self.currentPositionID = currentPositionID
        self.onJump = onJump
        _isPanelPresented = State(initialValue: initiallyExpanded)
    }

    /// スクラバーとパネルで共有する選択位置。ホバー中はその id、
    /// 非ホバー時はスクロール連動の現在位置、無ければ最新入力。
    private var selectedID: String? { activeID ?? currentPositionID ?? entries.last?.id }

    var body: some View {
        let _ = themeID
        if !entries.isEmpty {
            HStack(alignment: .center, spacing: DSSpacing.s) {
                scrubber
                    .onHover(perform: setScrubberHover)

                if isPanelPresented {
                    historyPanel
                        .onHover(perform: setPanelHover)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isPanelPresented)
            .onDisappear(perform: cancelPendingClose)
            .accessibilityLabel("入力履歴")
            .help("ポインタを置くと入力履歴を表示")
        }
    }

    /// 積み重ねた横線のスクラバー。選択中の線を長く・濃く強調する。
    /// 各線は不可視のヒット領域を持ち、ホバーで選択、クリックでジャンプする。
    private var scrubber: some View {
        let ticks = InputHistoryPolicy.scrubberTicks(from: entries, cap: Self.tickCap)
        let selected = selectedID
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(ticks) { tick in
                let isSelected = tick.id == selected
                Button {
                    jump(to: tick.id)
                } label: {
                    Capsule(style: .continuous)
                        .fill(isSelected ? DSColor.chatTextPrimary : DSColor.chatTextSecondary)
                        .frame(
                            width: isSelected ? DSSpacing.l : DSSpacing.m,
                            height: isSelected ? 2 : 1.5
                        )
                        .opacity(isSelected ? 1 : (hoveringScrubber ? 0.7 : 0.4))
                        .frame(width: Self.tickHitWidth, height: Self.tickHitHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { activeID = tick.id } }
                .accessibilityIdentifier("ChatInputHistoryScrubber.tick")
            }
        }
        .animation(.easeOut(duration: 0.15), value: selected)
        .animation(.easeOut(duration: 0.12), value: hoveringScrubber)
    }

    private var historyPanel: some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
        let selected = selectedID
        return ScrollView {
            LazyVStack(spacing: DSSpacing.xxs) {
                ForEach(entries) { entry in
                    ChatInputHistoryRow(
                        entry: entry,
                        isSelected: entry.id == selected,
                        onHover: { activeID = entry.id },
                        onJump: jump
                    )
                }
            }
            .padding(DSSpacing.s)
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: Self.panelMaxHeight)
        .clipShape(shape)
        .modifier(GlassPanelBackground(cornerRadius: DSRadius.l))
        .overlay {
            shape.strokeBorder(DSColor.separator, lineWidth: 1)
        }
        .dsShadow(.cardHover)
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

/// Liquid Glass 風のパネル面。macOS 26 以降は本物の `.glassEffect`、
/// それ未満は半透明マテリアルへフォールバックする。
private struct GlassPanelBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
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
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .fill(isSelected ? DSColor.fillSelected : Color.clear)
                )
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
