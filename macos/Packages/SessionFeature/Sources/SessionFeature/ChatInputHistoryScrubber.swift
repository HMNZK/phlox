import SwiftUI
import DesignSystem

/// チャットの過去入力へ素早く移動するための、左端の入力履歴スクラバー。
/// スクラバーと一覧パネルを同じ hover 領域に置き、ポインタ移動中のちらつきを防ぐ。
struct ChatInputHistoryScrubber: View {
    let entries: [InputHistoryEntry]
    let onJump: (String) -> Void

    private static let tickCap = 12
    private static let panelWidth: CGFloat = 320
    private static let panelMaxHeight: CGFloat = 320
    private static let closeDelay: Duration = .milliseconds(200)

    @State private var isPanelPresented: Bool
    @State private var closeTask: Task<Void, Never>? = nil
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    init(entries: [InputHistoryEntry], onJump: @escaping (String) -> Void, initiallyExpanded: Bool = false) {
        self.entries = entries
        self.onJump = onJump
        _isPanelPresented = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        let _ = themeID
        if !entries.isEmpty {
            HStack(alignment: .center, spacing: 0) {
                scrubber

                if isPanelPresented {
                    historyPanel
                        .padding(.leading, DSSpacing.s)
                }
            }
            // panel 表示後はスクラバーからパネルまでを一続きの hit 領域にする。
            .contentShape(Rectangle())
            .onHover(perform: updateHoverState)
            .onDisappear(perform: cancelPendingClose)
            .accessibilityLabel("入力履歴")
            .help("ポインタを置くと入力履歴を表示")
        }
    }

    private var scrubber: some View {
        let ticks = InputHistoryPolicy.scrubberTicks(from: entries, cap: Self.tickCap)
        return VStack(spacing: DSSpacing.xs) {
            ForEach(ticks.indices, id: \.self) { index in
                let isCurrent = index == ticks.indices.last
                Rectangle()
                    .fill(isCurrent ? DSColor.chatTextPrimary : DSColor.chatTextSecondary)
                    .frame(width: DSSpacing.l, height: isCurrent ? DSSpacing.xxs : 1)
                    .opacity(isCurrent ? 1 : 0.55)
            }
        }
        .padding(DSSpacing.s)
        .background(DSColor.chatBackground.opacity(0.88), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(DSColor.separator, lineWidth: 1)
        }
    }

    private var historyPanel: some View {
        VStack(spacing: 0) {
            Text("入力履歴")
                .font(DSFont.sectionHeader)
                .foregroundStyle(DSColor.chatTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)

            Divider().overlay(DSColor.separator)

            ScrollView {
                LazyVStack(spacing: DSSpacing.xs) {
                    ForEach(entries) { entry in
                        ChatInputHistoryRow(entry: entry, onJump: jump)
                    }
                }
                .padding(DSSpacing.s)
            }
            .frame(maxHeight: Self.panelMaxHeight)
        }
        .frame(width: Self.panelWidth)
        .background(DSColor.chatElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .strokeBorder(DSColor.separator, lineWidth: 1)
        }
        .dsShadow(.cardHover)
        .accessibilityIdentifier("ChatInputHistoryScrubber.panel")
    }

    private func updateHoverState(_ isHovering: Bool) {
        if isHovering {
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
            closeTask = nil
        }
    }

    private func cancelPendingClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func jump(to entryID: String) {
        cancelPendingClose()
        isPanelPresented = false
        onJump(entryID)
    }
}

private struct ChatInputHistoryRow: View {
    let entry: InputHistoryEntry
    let onJump: (String) -> Void

    @State private var isHovering = false

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
                        .fill(isHovering ? DSColor.fillSubtle : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
