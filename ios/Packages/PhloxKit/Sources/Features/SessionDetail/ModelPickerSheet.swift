import SwiftUI
import DesignSystemIOS
import PhloxCore

struct ModelPickerSheet: View {
    let entries: [SessionDetailViewModel.ModelPickerEntry]
    let selectedEntryID: String?
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if let activeEntry {
                    Section("Active") {
                        entryButton(activeEntry, isSelected: true)
                    }
                }

                Section("More") {
                    ForEach(moreEntries) { entry in
                        entryButton(entry, isSelected: false)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search")
            .navigationTitle("Model")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: onDismiss)
                }
            }
        }
    }

    private var filteredEntries: [SessionDetailViewModel.ModelPickerEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.kind.displayName.localizedCaseInsensitiveContains(query)
                || ($0.modelID?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var activeEntry: SessionDetailViewModel.ModelPickerEntry? {
        guard let selectedEntryID else { return nil }
        return filteredEntries.first(where: { $0.id == selectedEntryID })
    }

    private var moreEntries: [SessionDetailViewModel.ModelPickerEntry] {
        filteredEntries.filter { $0.id != selectedEntryID }
    }

    private func entryButton(
        _ entry: SessionDetailViewModel.ModelPickerEntry,
        isSelected: Bool
    ) -> some View {
        Button {
            onSelect(entry.id)
        } label: {
            HStack(spacing: DSSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(entry.kind.displayName)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                }
                Spacer(minLength: DSSpacing.s)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(DSFont.body.weight(.semibold))
                        .foregroundStyle(DSColor.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
