import DesignSystemIOS
import PhloxCore
import SwiftUI

struct ModelPickerSheet: View {
    let entries: [SessionDetailViewModel.ModelPickerEntry]
    let selectedEntryID: String?
    let agentName: String
    let defaultEntryID: String?
    let isChangingModelID: String?
    let failureMessage: String?
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""

    var body: some View {
        ModelSelectionSheet(
            title: "\(agentName) のモデル",
            searchText: $searchText,
            explanation: "このセッションのエージェントのモデルだけを選べます",
            onDismiss: onDismiss
        ) {
            if let failureMessage {
                Text(failureMessage)
                    .font(DSFont.iosCaption2)
                    .foregroundStyle(IOSColor.status.error)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            if filteredEntries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if let kind = entries.first?.kind {
                            DSAgentBrandIcon(kind: kind, size: 16)
                        }
                        Text(agentName)
                            .font(DSFont.subheadline.weight(.semibold))
                            .foregroundStyle(IOSColor.text.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            entryButton(entry)
                            if entry.id != filteredEntries.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    private var filteredEntries: [SessionDetailViewModel.ModelPickerEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || ($0.modelID?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func entryButton(_ entry: SessionDetailViewModel.ModelPickerEntry) -> some View {
        let isSelected = entry.id == selectedEntryID
        let isChanging = entry.modelID == isChangingModelID
        return Button {
            onSelect(entry.id)
        } label: {
            HStack(spacing: DSSpacing.s) {
                Text(entry.displayName)
                    .font(DSFont.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(IOSColor.text.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DSSpacing.s)
                if entry.id == defaultEntryID {
                    Text("既定")
                        .font(DSFont.iosCaption2.weight(.medium))
                        .foregroundStyle(IOSColor.text.secondary)
                        .padding(.horizontal, DSSpacing.s)
                        .padding(.vertical, 2)
                        .background(DSColor.fillSubtle, in: Capsule())
                }
                if isChanging {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark")
                        .font(DSFont.body.weight(.semibold))
                        .foregroundStyle(IOSColor.accent)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: DSTouch.minSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressFeedbackStyle())
        .disabled(isChangingModelID != nil)
        .accessibilityLabel(
            "\(entry.displayName)\(entry.id == defaultEntryID ? "、既定" : "")\(isSelected ? "、選択中" : "")"
        )
    }
}
