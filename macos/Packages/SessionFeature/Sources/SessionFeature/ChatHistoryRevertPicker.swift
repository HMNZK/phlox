import SwiftUI
import DesignSystem

/// esc 2連打で開く「会話を巻き戻す」履歴ピッカー（task-9 / Claude Code の double-esc rewind 相当）。
/// 過去のユーザーメッセージを新しい順に一覧し、選択でその時点まで会話を巻き戻す（task-8 revert）。
/// - クリック、または（ハイライト行を）Enter で確定 → `onConfirm(userMessageID)`。
/// - esc / 閉じるボタン / 背景タップで `onCancel`。
/// - 状態機械（2連打判定・ピッカー開閉）は ViewModel 側に持たせ、本ビューは表示と入力の受付のみ。
struct ChatHistoryRevertPicker: View {
    let candidates: [ChatItem]
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var selection: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DSColor.separator)
            listBody
        }
        .frame(maxWidth: 560, maxHeight: 480)
        .background(DSColor.chatElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .strokeBorder(DSColor.separator, lineWidth: 1)
        )
        .dsShadow(.cardHover)
        .focusable()
        .focused($isFocused)
        .onAppear {
            if selection == nil { selection = candidates.first?.id }
            isFocused = true
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        .onKeyPress(.return) {
            guard let selection else { return .ignored }
            onConfirm(selection)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .accessibilityIdentifier("ChatHistoryRevertPicker")
    }

    private var header: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(DSColor.chatAccent)
            Text("会話を巻き戻す")
                .font(DSFont.sectionHeader)
                .foregroundStyle(DSColor.chatTextPrimary)
            Spacer(minLength: DSSpacing.s)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: DSIconSize.m, weight: .semibold))
                    .foregroundStyle(DSColor.chatTextSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ChatHistoryRevertPicker.close")
            .help("閉じる")
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.vertical, DSSpacing.m)
    }

    @ViewBuilder
    private var listBody: some View {
        if candidates.isEmpty {
            Text("巻き戻せる履歴がありません")
                .font(DSFont.body)
                .foregroundStyle(DSColor.chatTextSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DSSpacing.xl)
        } else {
            ScrollView {
                LazyVStack(spacing: DSSpacing.xs) {
                    ForEach(candidates) { item in
                        row(for: item)
                    }
                }
                .padding(DSSpacing.s)
            }
        }
    }

    private func row(for item: ChatItem) -> some View {
        let isSelected = selection == item.id
        return Button {
            onConfirm(item.id)
        } label: {
            Text(messageText(item))
                .font(DSFont.body)
                .foregroundStyle(DSColor.chatTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .fill(isSelected ? DSColor.chatAccent.opacity(0.22) : DSColor.chatCard.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .strokeBorder(DSColor.chatAccent.opacity(isSelected ? 0.5 : 0), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { selection = item.id }
        }
        .accessibilityIdentifier("ChatHistoryRevertPicker.row")
    }

    private func messageText(_ item: ChatItem) -> String {
        if case .userMessage(_, let text, _, _) = item {
            return text
        }
        return ""
    }

    private func moveSelection(by delta: Int) {
        guard !candidates.isEmpty else { return }
        let ids = candidates.map(\.id)
        let currentIndex = selection.flatMap { ids.firstIndex(of: $0) } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), ids.count - 1)
        selection = ids[nextIndex]
    }
}
