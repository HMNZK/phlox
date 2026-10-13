import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// グリッドに表示するセッションを選択する popover 一覧。
struct GridSessionPicker: View {
    let candidates: [SessionNode]
    let isSelected: (SessionID) -> Bool
    let onToggle: (SessionID) -> Void
    let onShowAll: () -> Void

    private enum Row: Hashable { case showAll, session(SessionID) }
    @State private var hovered: Row?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onShowAll) {
                HStack(spacing: DSSpacing.s) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(DSColor.textSecondary)
                    Text("すべて表示")
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .dsPopupRowHighlight(hovered == .showAll)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { setHovered(.showAll, $0) }

            Divider().overlay(DSColor.separator)

            if candidates.isEmpty {
                Text("表示できるセッションがありません")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(DSSpacing.m)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(candidates, id: \.id) { session in
                            sessionRow(session)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(DSLayout.menuPadding)
        .frame(width: 260)
        .background(DSColor.popoverBackground)
    }

    /// 隣の行へ移ると「入った」が「出た」より先に届くことがあるので、出たときは自分が強調中のときだけ消す。
    private func setHovered(_ row: Row, _ inside: Bool) {
        if inside { hovered = row } else if hovered == row { hovered = nil }
    }

    private func sessionRow(_ session: SessionNode) -> some View {
        Button {
            onToggle(session.id)
        } label: {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: isSelected(session.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected(session.id) ? DSColor.textPrimary : DSColor.textSecondary)
                Text(session.displayName)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .dsPopupRowHighlight(hovered == .session(session.id))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { setHovered(.session(session.id), $0) }
    }
}
