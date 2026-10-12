import SwiftUI
import AppKit
import AgentDomain
import DesignSystem

/// セッションができる前の下書きと、新しいセッションの入力欄で共用する本文入力欄。
public struct ComposerDraftInput: View {
    @Binding private var text: String
    @Bindable private var attachmentStore: ComposerAttachmentStore
    private let workingDirectory: String
    private let placeholder: String
    private let focusToken: Int
    private let accessibilityPrefix: String
    private let inputAccessibilitySuffix: String
    private let onSubmit: () -> Void
    private let onCycleEffort: () -> Bool
    private let onFocusChange: ((Bool) -> Void)?
    private let onTab: (() -> Bool)?

    @State private var editorHeight = ComposerHeightBounds.single.min
    @State private var isComposing = false
    @State private var suggestionController: ComposerSuggestionController
    @Environment(\.localizationBundle) private var localizationBundle

    var accessibilityRole: String { "メッセージ" }
    var accessibilityValue: String { text }

    public init(
        text: Binding<String>,
        attachmentStore: ComposerAttachmentStore,
        workingDirectory: String,
        placeholder: String,
        focusToken: Int = 0,
        accessibilityPrefix: String = "ChatComposer",
        inputAccessibilitySuffix: String = "input",
        onSubmit: @escaping () -> Void,
        onCycleEffort: @escaping () -> Bool = { false },
        onFocusChange: ((Bool) -> Void)? = nil,
        onTab: (() -> Bool)? = nil
    ) {
        _text = text
        _attachmentStore = Bindable(wrappedValue: attachmentStore)
        self.workingDirectory = workingDirectory
        self.placeholder = placeholder
        self.focusToken = focusToken
        self.accessibilityPrefix = accessibilityPrefix
        self.inputAccessibilitySuffix = inputAccessibilitySuffix
        self.onSubmit = onSubmit
        self.onCycleEffort = onCycleEffort
        self.onFocusChange = onFocusChange
        self.onTab = onTab
        _suggestionController = State(wrappedValue: ComposerSuggestionController.production(workingDirectory: workingDirectory))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ComposerAttachmentStrip(store: attachmentStore, layout: .standard, onRemove: removeAttachment)
                .padding(.top, attachmentStore.attachments.isEmpty ? 0 : DSSpacing.s)
            ZStack(alignment: .topLeading) {
                IMESafeTextView(
                    text: $text,
                    isComposing: $isComposing,
                    measuredHeight: $editorHeight,
                    minHeight: ComposerHeightBounds.single.min,
                    maxHeight: ComposerHeightBounds.single.max,
                    suggestionController: suggestionController,
                    onSubmit: onSubmit,
                    onPasteImageOutcome: addPastedImage,
                    attachedImageNumbers: { attachmentStore.attachments.map(\.number) },
                    imagesForCopy: { attachmentStore.imagesForCopy(numbers: $0) },
                    onEscape: {},
                    focusRequest: ComposerFocusRequest(token: focusToken, movesCaretToEnd: true),
                    onFocusRequestHandled: { _ in },
                    highlightsKeywords: false,
                    onTab: onTab,
                    onRecallHistory: { _ in false },
                    onCycleEffort: onCycleEffort,
                    onFocusChange: { focused in
                        onFocusChange?(focused)
                    },
                    inputAccessibilityIdentifier: "\(accessibilityPrefix).\(inputAccessibilitySuffix)",
                    inputAccessibilityLabel: NSLocalizedString(accessibilityRole, bundle: localizationBundle, comment: ""),
                    tabMovesFocus: true
                )
                .frame(minHeight: ComposerHeightBounds.single.min, idealHeight: editorHeight, maxHeight: ComposerHeightBounds.single.max)
                .accessibilityLabel(Text(LocalizedStringKey(accessibilityRole), bundle: localizationBundle))
                .accessibilityValue(Text(verbatim: accessibilityValue))
                .accessibilityIdentifier("\(accessibilityPrefix).\(inputAccessibilitySuffix)")

                if ComposerPlaceholderVisibility.shouldShowPlaceholder(text: text, isComposing: isComposing) {
                    Text(placeholder)
                        .font(ComposerPlaceholderMetrics.placeholderFont)
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, ComposerPlaceholderMetrics.textInsets.width)
                        .padding(.vertical, ComposerPlaceholderMetrics.textInsets.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: editorHeight)
            .padding(.horizontal, -ComposerPlaceholderMetrics.textInsets.width)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10 - ComposerPlaceholderMetrics.textInsets.height)
        .padding(.bottom, 4)
        .overlay(alignment: .topLeading) {
            if suggestionController.isPresented {
                ComposerSuggestionPopup(controller: suggestionController, onAccept: acceptSuggestion)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("\(accessibilityPrefix).suggestions")
                    .padding(.leading, 10)
                    .placedAbove(gap: 6)
            }
        }
        .reportsComposerPopup(suggestionController.isPresented)
        .onChange(of: text) { oldValue, newValue in
            attachmentStore.removeAttachmentsMissing(fromOldText: oldValue, newText: newValue)
        }
    }

    private func acceptSuggestion(_ index: Int) {
        suggestionController.select(index)
        guard let replacement = suggestionController.acceptSelected() else { return }
        text = ComposerSuggestionTextReplacement.apply(replacement, to: text).text
    }

    private func addPastedImage(data: Data, mediaType: String) -> ComposerPasteImageOutcome {
        guard let attachment = attachmentStore.addImage(data: data, mediaType: mediaType) else { return .rejected }
        text = ComposerImagePlaceholder.inserting(number: attachment.number, into: text, cursorUTF16: text.utf16.count).text
        return .attached(number: attachment.number)
    }

    private func removeAttachment(_ attachment: ComposerAttachment) {
        attachmentStore.remove(id: attachment.id)
        text = ComposerImagePlaceholder.removing(number: attachment.number, from: text)
    }
}

public struct ComposerSettingOption: Hashable, Identifiable, Sendable {
    public let value: String?
    public let title: String
    public let isDefault: Bool
    public let isEnabled: Bool

    public var id: String { value ?? "" }

    public init(value: String?, title: String, isDefault: Bool = false, isEnabled: Bool = true) {
        self.value = value
        self.title = title
        self.isDefault = isDefault
        self.isEnabled = isEnabled
    }
}

public struct ComposerSettingChip: View {
    public let title: String
    public let options: [ComposerSettingOption]
    public let selection: String?
    public let onSelect: (String?) -> Void
    public let accessibilityIdentifier: String
    public let leadingSystemImage: String?
    public let showsFocusRing: Bool

    public init(title: String, options: [ComposerSettingOption], selection: String?,
                accessibilityIdentifier: String, leadingSystemImage: String? = nil,
                showsFocusRing: Bool = false,
                onSelect: @escaping (String?) -> Void) {
        self.title = title
        self.options = options
        self.selection = selection
        self.accessibilityIdentifier = accessibilityIdentifier
        self.leadingSystemImage = leadingSystemImage
        self.showsFocusRing = showsFocusRing
        self.onSelect = onSelect
    }

    public var body: some View {
        SelectablePopoverButton(
            options: options.map { option in
                SelectablePopoverOption(
                    id: option.id.isEmpty ? "__default" : option.id,
                    value: option.value,
                    title: option.title,
                    badge: option.isDefault ? "既定" : nil,
                    isSelected: selection == option.value,
                    isEnabled: option.isEnabled
                )
            },
            selectedID: options.first(where: { $0.value == selection }).map { $0.id.isEmpty ? "__default" : $0.id },
            accessibilityLabel: title,
            accessibilityValue: options.first(where: { $0.value == selection })?.title ?? "",
            accessibilityIdentifier: accessibilityIdentifier,
            help: title,
            showsFocusRing: showsFocusRing,
            onSelect: { onSelect($0.value) }
        ) { _ in
            ComposerChipLabel(title: title, leadingSystemImage: leadingSystemImage)
        }
    }
}
