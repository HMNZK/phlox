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

    /// PhloxChat.dc.html の showRevert: 幅 480・ポップオーバー地・角丸 12・内側 8。
    /// 見出しと説明 → 行（高さ 30・13pt・右に時刻。選択行はアクセント塗り＋白文字）→ 区切り線の下にキーの案内。
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("この発言の前まで巻き戻す")
                    .font(DSFont.row.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Text("選んだ発言以降の会話を取り消し、その発言を入力欄に戻します")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            listBody
            HStack(spacing: 14) {
                Text("↑↓ 選択")
                Text("↩ 巻き戻す")
                // 見た目はキーの案内のまま、押して閉じられる（VoiceOver からも閉じられる）。
                Button(action: onCancel) {
                    Text("Esc 閉じる")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("閉じる"))
                .accessibilityIdentifier("ChatHistoryRevertPicker.close")
                Spacer(minLength: 0)
                Text("実行中なら先に中断します")
            }
            .font(DSFont.meta)
            .foregroundStyle(DSColor.textTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .overlay(alignment: .top) {
                Rectangle().fill(DSColor.separator).frame(height: 1)
            }
            .padding(.top, 4)
        }
        .padding(8)
        .frame(width: 480)
        // 高さは中身に合わせる（maxHeight の柔軟な枠だと提示された高さいっぱいに広がり、中身が縦の中央に浮く）。
        .fixedSize(horizontal: false, vertical: true)
        .background(DSColor.popoverBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dsShadow(.cardHover)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("会話を巻き戻す"))
        .accessibilityIdentifier("ChatHistoryRevertPicker")
    }

    @ViewBuilder
    private var listBody: some View {
        if candidates.isEmpty {
            Text("巻き戻せる履歴がありません")
                .font(DSFont.row)
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(candidates) { item in
                        row(for: item)
                    }
                }
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(for item: ChatItem) -> some View {
        let isSelected = selection == item.id
        return Button {
            onConfirm(item.id)
        } label: {
            HStack(spacing: 10) {
                Text(messageText(item))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: Self.timeFormatter.string(from: item.timestamp))
                    .font(DSFont.meta)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white : DSColor.textSecondary)
                    .opacity(0.8)
            }
            .font(DSFont.row)
            .foregroundStyle(isSelected ? Color.white : DSColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? DSColor.accentFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { selection = item.id }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("ChatHistoryRevertPicker.row")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

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
