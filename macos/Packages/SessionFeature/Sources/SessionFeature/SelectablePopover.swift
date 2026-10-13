import SwiftUI
import AgentDomain
import DesignSystem

public struct SelectablePopoverOption: Hashable, Identifiable {
    public let id: String
    public let value: String?
    public let title: String
    public let sectionTitle: String?
    public let sectionAgent: AgentKind?
    public let detail: String?
    public let badge: String?
    public let leadingSystemImage: String?
    public let closeAccessibilityLabel: String?
    public let isSelected: Bool
    public let isEnabled: Bool
    public let isSelectable: Bool
    public let accessibilityHint: String?

    public init(
        id: String,
        value: String? = nil,
        title: String,
        sectionTitle: String? = nil,
        sectionAgent: AgentKind? = nil,
        detail: String? = nil,
        badge: String? = nil,
        leadingSystemImage: String? = nil,
        closeAccessibilityLabel: String? = nil,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        isSelectable: Bool = true,
        accessibilityHint: String? = nil
    ) {
        self.id = id
        self.value = value
        self.title = title
        self.sectionTitle = sectionTitle
        self.sectionAgent = sectionAgent
        self.detail = detail
        self.badge = badge
        self.leadingSystemImage = leadingSystemImage
        self.closeAccessibilityLabel = closeAccessibilityLabel
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isSelectable = isSelectable
        self.accessibilityHint = accessibilityHint
    }
}

struct SelectablePopoverNavigation: Equatable {
    enum HighlightSource: Equatable {
        case keyboard
        case pointer
    }

    private(set) var highlightedID: String?
    private(set) var highlightSource: HighlightSource = .keyboard

    mutating func reset(availableIDs: [String], selectedID: String?) {
        highlightSource = .keyboard
        highlightedID = selectedID.flatMap { availableIDs.contains($0) ? $0 : nil } ?? availableIDs.first
    }

    mutating func move(by offset: Int, among availableIDs: [String]) {
        highlightSource = .keyboard
        guard !availableIDs.isEmpty else { highlightedID = nil; return }
        let current = availableIDs.firstIndex(of: highlightedID ?? "") ?? (offset > 0 ? -1 : availableIDs.count)
        highlightedID = availableIDs[min(availableIDs.count - 1, max(0, current + offset))]
    }

    mutating func movePointer(to id: String, among availableIDs: [String]) {
        highlightSource = .pointer
        highlightedID = availableIDs.contains(id) ? id : nil
    }

    mutating func clearPointerHighlight(for id: String) {
        guard highlightSource == .pointer, highlightedID == id else { return }
        highlightedID = nil
    }

    func selectionID(among availableIDs: [String]) -> String? {
        highlightedID.flatMap { availableIDs.contains($0) ? $0 : nil }
    }
}

public struct SelectablePopover: View {
    public let options: [SelectablePopoverOption]
    public let selectedID: String?
    public let width: CGFloat
    public let maxHeight: CGFloat
    public let footer: String?
    public let searchText: Binding<String>?
    public let accessibilityIdentifier: String?
    public let onSelect: (SelectablePopoverOption) -> Void
    public let onClose: ((SelectablePopoverOption) -> Void)?
    public let onDismiss: () -> Void

    @Environment(\.locale) private var locale
    @State private var navigation = SelectablePopoverNavigation()
    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool

    public init(
        options: [SelectablePopoverOption],
        selectedID: String?,
        width: CGFloat = DSLayout.menuWidth,
        maxHeight: CGFloat = DSLayout.menuDefaultMaxHeight,
        footer: String? = nil,
        searchText: Binding<String>? = nil,
        accessibilityIdentifier: String? = nil,
        onSelect: @escaping (SelectablePopoverOption) -> Void,
        onClose: ((SelectablePopoverOption) -> Void)? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.options = options
        self.selectedID = selectedID
        self.width = width
        self.maxHeight = maxHeight
        self.footer = footer
        self.searchText = searchText
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onSelect = onSelect
        self.onClose = onClose
        self.onDismiss = onDismiss
    }

    private var query: String { searchText?.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" }
    private var visibleOptions: [SelectablePopoverOption] {
        guard !query.isEmpty else { return options }
        let matchingSections = Set(options.compactMap { option in
            option.sectionTitle?.localizedLowercase.contains(query) == true ? option.sectionTitle : nil
        })
        return options.filter {
            $0.id.localizedLowercase.contains(query)
                || $0.value?.localizedLowercase.contains(query) == true
                || $0.title.localizedLowercase.contains(query)
                || $0.detail?.localizedLowercase.contains(query) == true
                || $0.badge?.localizedLowercase.contains(query) == true
                || ($0.sectionTitle.map(matchingSections.contains) == true)
        }
    }
    private var selectableIDs: [String] { visibleOptions.filter { $0.isSelectable && $0.isEnabled }.map(\.id) }
    private var rowHeight: CGFloat { searchText == nil ? DSLayout.menuItemHeight : DSLayout.harnessMenuItemHeight }
    private var scrollHeight: CGFloat {
        let rows = visibleOptions.reduce(CGFloat.zero) { $0 + ($1.detail == nil ? rowHeight : DSLayout.menuDetailItemHeight) }
        let sectionCount = Set(visibleOptions.compactMap(\.sectionTitle)).count
        let sections = CGFloat(sectionCount) * DSLayout.menuSectionHeight
        let itemCount = visibleOptions.count + sectionCount
        let gaps = searchText == nil ? CGFloat(max(0, itemCount - 1)) * DSLayout.menuInterItemGap : 0
        let reserved: CGFloat = (searchText == nil ? 0 : DSLayout.menuSearchReservedHeight)
            + (footer == nil ? 0 : DSLayout.menuFooterReservedHeight)
            + DSLayout.menuPadding * 2
        return min(max(DSLayout.menuMinimumScrollHeight, rows + sections + gaps), max(DSLayout.menuMinimumScrollHeight, maxHeight - reserved))
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let searchText { searchField(searchText) }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: searchText == nil ? DSLayout.menuInterItemGap : 0) {
                        ForEach(Array(visibleOptions.enumerated()), id: \.element.id) { index, option in
                            if let section = option.sectionTitle,
                               index == 0 || visibleOptions[index - 1].sectionTitle != section {
                                sectionHeader(section, agent: option.sectionAgent)
                            }
                            SelectablePopoverRow(
                                option: option,
                                rowHeight: rowHeight,
                                isHighlighted: navigation.highlightSource == .keyboard && navigation.highlightedID == option.id,
                                isPointerHighlighted: navigation.highlightSource == .pointer && navigation.highlightedID == option.id,
                                onHoverChange: { hovering in
                                    if hovering {
                                        navigation.movePointer(to: option.id, among: selectableIDs)
                                    } else {
                                        navigation.clearPointerHighlight(for: option.id)
                                    }
                                },
                                canClose: onClose != nil,
                                onSelect: { choose(option) },
                                onClose: { onClose?(option) }
                            )
                            .id(option.id)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .frame(height: scrollHeight)
                .onChange(of: navigation.highlightedID) { _, id in
                    if navigation.highlightSource == .keyboard, let id {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            if let footer {
                Text(verbatim: footer)
                    .font(DSFont.meta)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DSLayout.menuFooterHorizontalInset)
                    .padding(.top, DSLayout.menuFooterTopInset)
                    .padding(.bottom, DSLayout.menuFooterBottomInset)
                    .overlay(alignment: .top) {
                        Rectangle().fill(DSColor.separator).frame(height: 1).padding(.horizontal, DSLayout.menuFooterSeparatorInset)
                    }
            }
        }
        .padding(DSLayout.menuPadding)
        .frame(width: width)
        .dsPopupSurface()
        .focusable(searchText == nil)
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.return) { chooseHighlighted() }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onAppear {
            navigation.reset(availableIDs: selectableIDs, selectedID: selectedID)
            if searchText == nil { listFocused = true } else { searchFocused = true }
        }
        .onChange(of: selectableIDs) { _, ids in navigation.reset(availableIDs: ids, selectedID: selectedID) }
        .onChange(of: query) { _, _ in navigation.reset(availableIDs: selectableIDs, selectedID: nil) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private func searchField(_ text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textTertiary)
                .accessibilityHidden(true)
            TextField(localized("モデルを絞り込む"), text: text)
                .font(DSFont.auxiliary)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.downArrow) { move(by: 1) }
                .onKeyPress(.upArrow) { move(by: -1) }
                .onKeyPress(.return) { chooseHighlighted() }
                .onKeyPress(.escape) { onDismiss(); return .handled }
                .accessibilityIdentifier("newChat.modelSearch")
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(DSColor.fieldBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DSColor.fieldBorder, lineWidth: 1))
        .padding(.horizontal, 3)
        .padding(.top, 3)
        .padding(.bottom, 5)
    }

    private func sectionHeader(_ title: String, agent: AgentKind?) -> some View {
        HStack(spacing: 6) {
            if let agent { AgentBrandIcon(kind: agent, size: 13) }
            Text(verbatim: title)
                .font(DSFont.meta.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: DSLayout.menuSectionHeight)
        .accessibilityElement(children: .combine)
    }

    private func move(by offset: Int) -> KeyPress.Result {
        navigation.move(by: offset, among: selectableIDs)
        return .handled
    }

    private func chooseHighlighted() -> KeyPress.Result {
        guard let id = navigation.selectionID(among: selectableIDs),
              let option = visibleOptions.first(where: { $0.id == id }) else { return .handled }
        choose(option)
        return .handled
    }

    private func choose(_ option: SelectablePopoverOption) {
        guard option.isSelectable, option.isEnabled else { return }
        onSelect(option)
    }

    private func localized(_ key: String) -> String {
        AppLocalizedString.string(key, locale: locale)
    }
}

public struct SelectablePopoverButton<Label: View>: View {
    public let options: [SelectablePopoverOption]
    public let selectedID: String?
    public let accessibilityLabel: String
    public let accessibilityValue: String
    public let accessibilityIdentifier: String
    public let help: String?
    public let width: CGFloat
    public let maxHeight: CGFloat
    public let footer: String?
    public let searchText: Binding<String>?
    public let isEnabled: Bool
    public let showsFocusRing: Bool
    public let onSelect: (SelectablePopoverOption) -> Void
    public let onClose: ((SelectablePopoverOption) -> Void)?
    @ViewBuilder public let label: (Bool) -> Label

    @State private var isPresented = false
    @FocusState private var triggerFocused: Bool

    public init(
        options: [SelectablePopoverOption],
        selectedID: String?,
        accessibilityLabel: String,
        accessibilityValue: String,
        accessibilityIdentifier: String,
        help: String? = nil,
        width: CGFloat = DSLayout.menuWidth,
        maxHeight: CGFloat = DSLayout.menuDefaultMaxHeight,
        footer: String? = nil,
        searchText: Binding<String>? = nil,
        isEnabled: Bool = true,
        showsFocusRing: Bool = false,
        onSelect: @escaping (SelectablePopoverOption) -> Void,
        onClose: ((SelectablePopoverOption) -> Void)? = nil,
        @ViewBuilder label: @escaping (Bool) -> Label
    ) {
        self.options = options
        self.selectedID = selectedID
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accessibilityIdentifier = accessibilityIdentifier
        self.help = help
        self.width = width
        self.maxHeight = maxHeight
        self.footer = footer
        self.searchText = searchText
        self.isEnabled = isEnabled
        self.showsFocusRing = showsFocusRing
        self.onSelect = onSelect
        self.onClose = onClose
        self.label = label
    }

    public var body: some View {
        Button { isPresented = true } label: { label(isPresented).contentShape(RoundedRectangle(cornerRadius: DSRadius.row)) }
            .buttonStyle(HoverableSurfaceButtonStyle(cornerRadius: DSRadius.row, hoverFill: DSColor.fillSubtle, hoverBorderColor: .clear))
            .focusable()
            .modifier(SelectablePopoverFocusEffectSuppression(isEnabled: showsFocusRing))
            .focused($triggerFocused)
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in isPresented = true; return .handled }
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                SelectablePopover(
                    options: options,
                    selectedID: selectedID,
                    width: width,
                    maxHeight: maxHeight,
                    footer: footer,
                    searchText: searchText,
                    accessibilityIdentifier: "\(accessibilityIdentifier).menu",
                    onSelect: { option in onSelect(option); isPresented = false },
                    onClose: onClose,
                    onDismiss: { isPresented = false }
                )
            }
            .onChange(of: isPresented) { _, presented in if !presented { triggerFocused = true } }
            .overlay {
                if showsFocusRing && triggerFocused && !isPresented {
                    RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                        // 白黒のアクセントでは focusRing の 2pt が強すぎるので、控えめな 1pt にする（2026-10-13 ユーザー指示）。
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

private struct SelectablePopoverRow: View {
    let option: SelectablePopoverOption
    let rowHeight: CGFloat
    let isHighlighted: Bool
    let isPointerHighlighted: Bool
    let onHoverChange: (Bool) -> Void
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @Environment(\.locale) private var locale
    @State private var isHovering = false

    private var rowLabel: String {
        [option.title, option.badge].compactMap { $0 }.joined(separator: "、")
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: DSLayout.menuItemGap) {
                    Image(systemName: option.isSelected ? "checkmark" : "")
                        .font(DSFont.meta.weight(.semibold))
                        .frame(width: DSLayout.menuCheckColumnWidth, height: DSLayout.menuTextLineHeight)
                    if let agent = option.sectionAgent, option.sectionTitle == nil {
                        AgentBrandIcon(kind: agent, size: DSLayout.controlChipIconSize)
                    } else if let icon = option.leadingSystemImage {
                        Image(systemName: icon)
                            .font(DSFont.auxiliary)
                            .frame(width: DSLayout.menuIconColumnWidth, height: DSLayout.menuTextLineHeight)
                    }
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(verbatim: option.title)
                            .font(DSFont.row)
                            .foregroundStyle(option.isEnabled ? DSColor.textPrimary : DSColor.textTertiary)
                            .lineLimit(1)
                        if let detail = option.detail {
                            Text(verbatim: detail)
                                .font(DSFont.meta)
                                .foregroundStyle(DSColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if let badge = option.badge {
                        Text(verbatim: badge)
                            .font(DSFont.meta.weight(.medium))
                            .foregroundStyle(DSColor.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.leading, DSLayout.menuItemLeadingInset)
                .padding(.trailing, DSLayout.menuItemTrailingInset)
                .padding(.vertical, option.detail == nil ? DSLayout.menuItemVerticalInset : DSLayout.menuDetailVerticalInset)
                .frame(maxWidth: .infinity, minHeight: option.detail == nil ? rowHeight : DSLayout.menuDetailItemHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!option.isEnabled || !option.isSelectable)
            .accessibilityLabel(Text(verbatim: rowLabel))
            .accessibilityValue(Text(verbatim: option.isSelected ? localized("選択中") : ""))
            .accessibilityHint(Text(verbatim: option.accessibilityHint ?? option.detail ?? ""))
            .accessibilityAddTraits(option.isSelected ? [.isSelected] : [])

            if isHovering, canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DSColor.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(option.closeAccessibilityLabel ?? localized("閉じる")))
                .accessibilityLabel(Text(option.closeAccessibilityLabel ?? localized("閉じる")))
            }
        }
        .dsPopupRowHighlight(isHighlighted || (isPointerHighlighted && isHovering))
        .onHover {
            isHovering = $0
            onHoverChange($0)
        }
        .accessibilityElement(children: .contain)
    }

    private func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale) }
}

private struct SelectablePopoverFocusEffectSuppression: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}
