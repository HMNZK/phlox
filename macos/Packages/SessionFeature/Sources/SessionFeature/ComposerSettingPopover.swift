import AppKit
import AgentDomain
import SwiftUI
import DesignSystem

public struct ComposerSettingChipLabel: View {
    let title: String?
    let systemImage: String?
    let harnessKind: AgentKind?
    let compact: Bool
    let usesMiddleTruncation: Bool
    let allowsTruncation: Bool
    let showsChevron: Bool

    public init(
        title: String?,
        systemImage: String? = nil,
        harnessKind: AgentKind? = nil,
        compact: Bool = false,
        usesMiddleTruncation: Bool = false,
        allowsTruncation: Bool = false,
        showsChevron: Bool = true
    ) {
        self.title = title
        self.systemImage = systemImage
        self.harnessKind = harnessKind
        self.compact = compact
        self.usesMiddleTruncation = usesMiddleTruncation
        self.allowsTruncation = allowsTruncation
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: DSLayout.controlChipContentGap) {
            if let harnessKind {
                AgentBrandIcon(kind: harnessKind, size: DSLayout.controlChipIconSize)
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(DSFont.controlIcon)
                    .frame(width: DSLayout.controlChipIconSize, height: DSLayout.controlChipIconSize)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            if let title, !compact {
                Text(verbatim: title)
                    .font(DSFont.auxiliary)
                    .lineLimit(1)
                    .truncationMode(usesMiddleTruncation ? .middle : .tail)
                    .fixedSize(horizontal: !allowsTruncation, vertical: false)
            }
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(DSFont.controlChevron)
                    .frame(width: DSLayout.controlChipChevronSize, height: DSLayout.controlChipChevronSize)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
        .fixedSize(horizontal: !allowsTruncation, vertical: false)
        .foregroundStyle(DSColor.textSecondary)
        .padding(.horizontal, DSLayout.controlChipHorizontalPadding)
        .frame(height: DSLayout.controlChipHeight)
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous))
    }
}

public struct ComposerSettingPopover<Label: View, Content: View>: View {
    private let accessibilityLabel: String
    private let accessibilityValue: String
    private let accessibilityIdentifier: String
    private let help: String?
    private let showsFocusRing: Bool
    private let isEnabled: Bool
    private let label: (Bool) -> Label
    private let content: (@escaping () -> Void) -> Content
    @State private var isPresented = false
    @State private var id = UUID()
    @FocusState private var triggerFocused: Bool

    public init(
        accessibilityLabel: String,
        accessibilityValue: String = "",
        accessibilityIdentifier: String,
        help: String? = nil,
        showsFocusRing: Bool = false,
        isEnabled: Bool = true,
        @ViewBuilder label: @escaping (Bool) -> Label,
        @ViewBuilder content: @escaping (@escaping () -> Void) -> Content
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accessibilityIdentifier = accessibilityIdentifier
        self.help = help
        self.showsFocusRing = showsFocusRing
        self.isEnabled = isEnabled
        self.label = label
        self.content = content
    }

    public var body: some View {
        Button { isPresented = true } label: { label(isPresented).contentShape(RoundedRectangle(cornerRadius: DSRadius.row)) }
            .buttonStyle(HoverableSurfaceButtonStyle(cornerRadius: DSRadius.row, hoverFill: DSColor.fillSubtle, hoverBorderColor: .clear))
            .focusable()
            .modifier(SelectablePopoverFocusEffectSuppression(isEnabled: showsFocusRing))
            .focused($triggerFocused)
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in isPresented = true; return .handled }
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                content { isPresented = false }
                    .onExitCommand { isPresented = false }
            }
            .onChange(of: isPresented) { _, presented in
                if presented { NotificationCenter.default.post(name: .composerPopupDidOpen, object: id) }
                else { triggerFocused = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .composerPopupDidOpen)) { notification in
                if notification.object as? UUID != id { isPresented = false }
            }
            .overlay {
                if showsFocusRing && triggerFocused && !isPresented {
                    RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                        .strokeBorder(DSColor.textSecondary, lineWidth: 1)
                }
            }
            .disabled(!isEnabled)
            .accessibilityLabel(Text(verbatim: accessibilityLabel))
            .accessibilityValue(Text(verbatim: accessibilityValue))
            .accessibilityIdentifier(accessibilityIdentifier)
            .help(Text(verbatim: help ?? accessibilityLabel))
    }
}

extension ComposerSettingPopover where Content == SelectablePopover {
    public init(
        options: [SelectablePopoverOption],
        selectedID: String?,
        accessibilityLabel: String,
        accessibilityValue: String = "",
        accessibilityIdentifier: String,
        help: String? = nil,
        width: CGFloat = DSLayout.menuWidth,
        maxHeight: CGFloat = DSLayout.menuDefaultMaxHeight,
        footer: String? = nil,
        searchText: Binding<String>? = nil,
        searchAccessibilityIdentifier: String? = nil,
        showsFocusRing: Bool = false,
        isEnabled: Bool = true,
        onSelect: @escaping (SelectablePopoverOption) -> Void,
        @ViewBuilder label: @escaping (Bool) -> Label
    ) {
        self.init(accessibilityLabel: accessibilityLabel, accessibilityValue: accessibilityValue,
                  accessibilityIdentifier: accessibilityIdentifier, help: help,
                  showsFocusRing: showsFocusRing, isEnabled: isEnabled, label: label) { dismiss in
            SelectablePopover(options: options, selectedID: selectedID, width: width,
                              maxHeight: maxHeight, footer: footer, searchText: searchText,
                              searchAccessibilityIdentifier: searchAccessibilityIdentifier ?? "\(accessibilityIdentifier).search",
                              accessibilityIdentifier: "\(accessibilityIdentifier).menu",
                              onSelect: { option in onSelect(option); dismiss() }, onDismiss: dismiss)
        }
    }
}

public func composerModelPickerFooter(languageCode: String) -> String {
    languageCode == "en"
        ? "↑↓ Move · ↩ Select · Type to filter · Esc Close"
        : "↑↓ 移動 · ↩ 決定 · 文字入力で絞り込み · Esc 閉じる"
}

struct SelectablePopoverFocusEffectSuppression: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled { content.focusEffectDisabled() }
        else { content }
    }
}
