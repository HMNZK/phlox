import SwiftUI
import DesignSystemIOS
import PhloxCore

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
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: DSSpacing.s) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(IOSColor.text.secondary)
                    TextField("絞り込み", text: $searchText)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #endif
                        .accessibilityLabel("モデルを絞り込む")
                }
                .font(DSFont.body)
                .padding(.horizontal, DSSpacing.m)
                .frame(height: 40)
                .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, DSSpacing.l)
                .padding(.top, DSSpacing.s)

                List {
                    if let failureMessage {
                        Text(failureMessage)
                            .font(DSFont.caption)
                            .foregroundStyle(IOSColor.status.error)
                            .listRowBackground(IOSColor.status.error.opacity(0.08))
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    if filteredEntries.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        Section {
                            ForEach(filteredEntries) { entry in
                                entryButton(entry)
                                    .listRowInsets(EdgeInsets(top: 0, leading: DSSpacing.m, bottom: 0, trailing: DSSpacing.m))
                            }
                        } header: {
                            HStack(spacing: DSSpacing.s) {
                                if let kind = entries.first?.kind {
                                    DSAgentBrandIcon(kind: kind, size: 18)
                                }
                                Text(agentName)
                            }
                            .textCase(nil)
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("\(agentName) のモデル")
            .tint(IOSColor.text.primary)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        Text("閉じる")
                            .font(DSFont.body.weight(.semibold))
                            .foregroundStyle(IOSColor.text.primary)
                            .padding(.horizontal, DSSpacing.m)
                            .frame(minHeight: DSTouch.minSize)
                            .background(DSColor.fillSubtle, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("このセッションのエージェントのモデルだけを選べます")
                    .font(DSFont.caption)
                    .foregroundStyle(IOSColor.text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.l)
                    .padding(.top, DSSpacing.s)
                    .padding(.bottom, DSSpacing.m)
                    .background(.regularMaterial)
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
                    .lineLimit(1)
                Spacer(minLength: DSSpacing.s)
                if entry.id == defaultEntryID {
                    Text("既定")
                        .font(DSFont.captionStrong)
                        .foregroundStyle(IOSColor.text.secondary)
                        .padding(.horizontal, DSSpacing.s)
                        .padding(.vertical, 2)
                        .background(DSColor.fillSubtle, in: Capsule())
                }
                if isChanging {
                    ProgressView().controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(DSFont.body.weight(.semibold))
                        .foregroundStyle(IOSColor.accent)
                }
            }
            .frame(minHeight: DSTouch.minSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isChangingModelID != nil)
        .accessibilityLabel(
            "\(entry.displayName)\(entry.id == defaultEntryID ? "、既定" : "")\(isSelected ? "、選択中" : "")"
        )
    }
}
