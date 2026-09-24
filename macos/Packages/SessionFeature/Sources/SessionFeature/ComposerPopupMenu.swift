import SwiftUI
import AppKit
import DesignSystem

/// 入力欄の下段のチップ（PhloxReply.dc.html の chip）: 高さ 22・左右 8・角丸 6・`--segBg` の面・11.5pt・末尾に 9pt の ▾。
/// 開いている間は `--sel` の面＋ fg3 の 1pt の内枠。ブランチは等幅 11・面なし・▾ なし。
struct ComposerChipLabel: View {
    let title: String
    var isOpen = false
    var isBranch = false
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: title)
                .font(.system(size: isBranch ? 11 : 11.5, design: isBranch ? .monospaced : .default))
                .lineLimit(1)
                .truncationMode(.middle)
            if let trailing { trailing }
            if !isBranch {
                Text(verbatim: "▾")
                    .font(.system(size: 9))
                    .opacity(0.7)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(DSColor.textPrimary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if isOpen {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DSColor.textTertiary, lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var background: Color {
        if isOpen { return DSColor.selectionFill }
        return isBranch ? .clear : DSColor.segmentTrack
    }
}

/// 入力欄の上に浮かせる箱（PhloxReply.dc.html の popover）: `--popover` の面・影・0.5pt の縁。
struct ComposerPopupSurface<Content: View>: View {
    var width: CGFloat
    var cornerRadius: CGFloat = 9
    var padding: CGFloat = 5
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(width: width, alignment: .leading)
            .background(DSColor.popoverBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DSColor.popoverEdge, lineWidth: 0.5)
            )
            .dsShadow(.popover)
    }
}

/// 開いている箱へ渡すキー（入力欄にフォーカスを残したまま ↑↓↩ で選べるように）。
struct ComposerPopupKeyEvent: Equatable {
    enum Key { case up, down, confirm }
    let key: Key
    let token: Int
}

extension EnvironmentValues {
    @Entry var composerPopupKey: ComposerPopupKeyEvent? = nil
}

/// 入力欄の上に何か（箱・候補・ツールチップ）が開いているか。入力履歴の目盛りを隠すのに使う（上に重なるので）。
struct ComposerPopupOpenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func reportsComposerPopup(_ isOpen: Bool) -> some View {
        transformPreference(ComposerPopupOpenKey.self) { $0 = $0 || isOpen }
    }
}

extension Notification.Name {
    /// 箱が開いたとき。ほかの箱を閉じる（object は開いた箱の id）。
    static let composerPopupDidOpen = Notification.Name("ComposerPopupDidOpen")
}

/// チップの上に箱を出す。外をクリック・Esc で閉じる。箱は入力欄の外（上）へはみ出して描く。
/// フォーカスは入力欄に残す。Esc は常に、↑↓↩ は入力欄にフォーカスがあるときだけ箱が受け取る。
/// ponytail: 外のクリックは NSEvent のローカル監視と SwiftUI の global 座標で判定する（ウィンドウの中身の左上が原点の前提）。
struct ComposerPopupPresenter<Popup: View>: ViewModifier {
    @Binding var isPresented: Bool
    var alignment: HorizontalAlignment = .leading
    var gap: CGFloat = 6
    @ViewBuilder let popup: () -> Popup
    @State private var anchorFrame: CGRect = .zero
    @State private var popupFrame: CGRect = .zero
    @State private var monitor: Any?
    @State private var openObserver: NSObjectProtocol?
    @State private var keyEvent: ComposerPopupKeyEvent?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .background(FrameReader(frame: $anchorFrame))
            .overlay(alignment: alignment == .trailing ? .topTrailing : .topLeading) {
                if isPresented {
                    popup()
                        .environment(\.composerPopupKey, keyEvent)
                        .fixedSize()
                        .background(FrameReader(frame: $popupFrame))
                        .placedAbove(gap: gap)
                        .onKeyPress(.escape) {
                            isPresented = false
                            return .handled
                        }
                        .transition(.opacity)
                }
            }
            .onChange(of: isPresented) { _, presented in
                presented ? installMonitor() : removeMonitor()
            }
            .onDisappear { removeMonitor() }
            // 開いている間は隣のチップより手前に描く（後ろのチップに隠れないように）。
            .zIndex(isPresented ? 1 : 0)
            .reportsComposerPopup(isPresented)
    }

    private func installMonitor() {
        removeMonitor()
        NotificationCenter.default.post(name: .composerPopupDidOpen, object: id)
        let ownID = id
        openObserver = NotificationCenter.default.addObserver(forName: .composerPopupDidOpen, object: nil, queue: .main) { note in
            guard (note.object as? UUID) != ownID else { return }
            MainActor.assumeIsolated { isPresented = false }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
            if event.type == .keyDown { return handleKey(event) }
            guard let contentView = event.window?.contentView else { return event }
            let location = event.locationInWindow
            let point = CGPoint(x: location.x, y: contentView.bounds.height - location.y)
            // チップの上は Button が開閉するので、ここでは閉じない（閉じてすぐ開き直さないように）。
            if !popupFrame.contains(point) && !anchorFrame.contains(point) {
                isPresented = false
            }
            return event
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let textView = event.window?.firstResponder as? NSTextView
        // 日本語の変換中のキー（Esc・↩・↑↓）は IME のもの。
        if textView?.hasMarkedText() == true { return event }
        let key: ComposerPopupKeyEvent.Key
        switch event.keyCode {
        case 53:
            isPresented = false
            return nil
        case 126: key = .up
        case 125: key = .down
        case 36, 76: key = .confirm
        default: return event
        }
        // ⇧↩（改行）や ⌘↑ など修飾付きは入力欄に任せる。
        guard event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty else { return event }
        // 検索欄など箱の中の欄にフォーカスがあるときは、その欄が自分で処理する。入力欄とチップ（キーボードで開いたとき）からは中継する。
        if let textView, !(textView is IMESafeTextView.SubmitAwareTextView) { return event }
        keyEvent = ComposerPopupKeyEvent(key: key, token: (keyEvent?.token ?? 0) + 1)
        return nil
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let openObserver { NotificationCenter.default.removeObserver(openObserver) }
        openObserver = nil
    }
}

private struct FrameReader: View {
    @Binding var frame: CGRect

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { frame = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { _, newValue in frame = newValue }
        }
    }
}

extension View {
    /// 親の上端の上に、下端を合わせて置く（間は `gap`）。overlay(alignment: .top…) の中で使う。
    /// 高さ 0 の枠の下端に揃えるので、alignmentGuide を使わずに上へはみ出させられる。
    func placedAbove(gap: CGFloat) -> some View {
        fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, gap)
            .frame(height: 0, alignment: .bottom)
    }

    func composerPopup<Popup: View>(
        isPresented: Binding<Bool>,
        alignment: HorizontalAlignment = .leading,
        gap: CGFloat = 6,
        @ViewBuilder popup: @escaping () -> Popup
    ) -> some View {
        modifier(ComposerPopupPresenter(isPresented: isPresented, alignment: alignment, gap: gap, popup: popup))
    }
}

/// 箱の中の 1 行（✓ の列 14 → 名前 → 右の注記）。
struct ComposerMenuRow: Identifiable {
    let id: String
    let title: String
    var note: String? = nil
    var isSelected = false
    var isEnabled = true
    let action: () -> Void
}

struct ComposerMenuSection: Identifiable {
    let id: String
    var title: String? = nil
    let rows: [ComposerMenuRow]
}

/// 選ぶだけの一覧（モデル・effort・ブランチ）。↑↓ で移動、↩ で決める、Esc で閉じる。
/// 指している行（ポインタ・キー）は `--accentFill` に白。選んである行は ✓。
struct ComposerMenuList<Footer: View>: View {
    var header: String? = nil
    var search: Binding<String>? = nil
    var searchPlaceholder: String = ""
    let sections: [ComposerMenuSection]
    var rowHeight: CGFloat = 24
    var monospacedRows = false
    let onClose: () -> Void
    @ViewBuilder var footer: () -> Footer
    @State private var highlightedID: String?
    @FocusState private var isFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @Environment(\.composerPopupKey) private var popupKey

    private var enabledRows: [ComposerMenuRow] {
        sections.flatMap(\.rows).filter(\.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(verbatim: header)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
            if let search {
                TextField(text: search) { Text(verbatim: searchPlaceholder) }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(DSColor.segmentTrack, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.horizontal, 3)
                    .padding(.top, 2)
                    .padding(.bottom, 5)
                    .focused($isSearchFocused)
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.return) { activateHighlighted() }
                    .accessibilityLabel(Text(verbatim: searchPlaceholder))
            }
            ForEach(sections) { section in
                if let title = section.title {
                    Text(verbatim: title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DSColor.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .padding(.bottom, 3)
                }
                ForEach(section.rows) { row in
                    rowView(row)
                }
            }
            footer()
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.return) { activateHighlighted() }
        .onChange(of: popupKey) { _, event in
            switch event?.key {
            case .up?: _ = move(-1)
            case .down?: _ = move(1)
            case .confirm?: _ = activateHighlighted()
            case nil: break
            }
        }
        .onAppear {
            highlightedID = enabledRows.first(where: \.isSelected)?.id ?? enabledRows.first?.id
        }
        // 検索で候補が絞られたら、指している行を残っている先頭へ移す。
        .onChange(of: enabledRows.map(\.id)) { _, ids in
            if let highlightedID, ids.contains(highlightedID) { return }
            highlightedID = ids.first
        }
        // 検索欄は書けるようにフォーカスを移す（出た直後は効かないので次の周回で）。
        .task {
            guard search != nil else { return }
            try? await Task.sleep(for: .milliseconds(50))
            isSearchFocused = true
        }
    }

    private func rowView(_ row: ComposerMenuRow) -> some View {
        let isHighlighted = row.isEnabled && highlightedID == row.id
        return Button {
            row.action()
            onClose()
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: row.isSelected ? "✓" : "")
                    .frame(width: 14, alignment: .leading)
                Text(verbatim: row.title)
                    .font(.system(size: monospacedRows ? 12 : 13, design: monospacedRows ? .monospaced : .default))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let note = row.note {
                    Text(verbatim: note)
                        .font(.system(size: 11))
                        .opacity(0.75)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(isHighlighted ? Color.white : (row.isEnabled ? DSColor.textPrimary : DSColor.textTertiary))
            .padding(.horizontal, 10)
            .frame(height: rowHeight)
            .background(isHighlighted ? DSColor.accentFill : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.isEnabled)
        .onHover { if $0 && row.isEnabled { highlightedID = row.id } }
        .accessibilityLabel(Text(verbatim: row.note.map { "\(row.title)、\($0)" } ?? row.title))
        .accessibilityAddTraits(row.isSelected ? .isSelected : [])
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let rows = enabledRows
        guard !rows.isEmpty else { return .handled }
        let current = rows.firstIndex { $0.id == highlightedID } ?? (delta > 0 ? -1 : rows.count)
        highlightedID = rows[max(0, min(rows.count - 1, current + delta))].id
        return .handled
    }

    private func activateHighlighted() -> KeyPress.Result {
        guard let row = enabledRows.first(where: { $0.id == highlightedID }) else { return .ignored }
        row.action()
        onClose()
        return .handled
    }
}

extension ComposerMenuList where Footer == EmptyView {
    init(
        header: String? = nil,
        search: Binding<String>? = nil,
        searchPlaceholder: String = "",
        sections: [ComposerMenuSection],
        rowHeight: CGFloat = 24,
        monospacedRows: Bool = false,
        onClose: @escaping () -> Void
    ) {
        self.init(
            header: header,
            search: search,
            searchPlaceholder: searchPlaceholder,
            sections: sections,
            rowHeight: rowHeight,
            monospacedRows: monospacedRows,
            onClose: onClose,
            footer: { EmptyView() }
        )
    }
}

/// 権限の箱（PhloxReply.dc.html の O4〜O6）: 題と件数 → ラジオの 2 行項目 → 区切り線 → Plan モードのスイッチ → 脚注。
struct ComposerPermissionPanel: View {
    let title: String
    let subtitle: String
    let options: [ComposerModeOption]
    let isSelected: (ComposerModeOption) -> Bool
    let isPlanOn: Bool
    let isPlanAvailable: Bool
    let footnote: String
    let onSelect: (ComposerModeOption) -> Void
    let onPlanChange: (Bool) -> Void
    let onClose: () -> Void
    @State private var highlightedIndex = 0
    @FocusState private var isFocused: Bool
    @Environment(\.composerPopupKey) private var popupKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DSColor.textTertiary)
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    optionRow(option, index: index)
                }
            }
            Rectangle()
                .fill(DSColor.separator)
                .frame(height: 1)
                .padding(.horizontal, 4)
            Toggle(isOn: Binding(get: { isPlanOn }, set: { onPlanChange($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Plan モード")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("計画だけを立て、ファイルの変更やコマンドは実行しない")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!isPlanAvailable)
            .accessibilityLabel(Text("Plan モード"))
            .accessibilityHint(Text("計画だけを立て、ファイルの変更やコマンドは実行しない"))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            Text(verbatim: footnote)
                .font(.system(size: 11))
                .foregroundStyle(DSColor.textTertiary)
                .padding(.horizontal, 4)
        }
        .foregroundStyle(DSColor.textPrimary)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.upArrow) { moveHighlight(-1) }
        .onKeyPress(.downArrow) { moveHighlight(1) }
        .onKeyPress(.return) {
            guard options.indices.contains(highlightedIndex) else { return .ignored }
            onSelect(options[highlightedIndex])
            onClose()
            return .handled
        }
        .onChange(of: popupKey) { _, event in
            switch event?.key {
            case .up?: _ = moveHighlight(-1)
            case .down?: _ = moveHighlight(1)
            case .confirm?:
                guard options.indices.contains(highlightedIndex) else { return }
                onSelect(options[highlightedIndex])
                onClose()
            case nil: break
            }
        }
        .onAppear {
            highlightedIndex = options.firstIndex(where: isSelected) ?? 0
        }
    }

    private func optionRow(_ option: ComposerModeOption, index: Int) -> some View {
        let selected = isSelected(option)
        return Button {
            onSelect(option)
            onClose()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .strokeBorder(selected ? DSColor.accentFill : DSColor.textTertiary, lineWidth: selected ? 4 : 1.2)
                    .frame(width: 14, height: 14)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: option.title)
                        .font(.system(size: 12.5, weight: .medium))
                    Text(verbatim: option.explanation)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                selected || highlightedIndex == index ? DSColor.fillSubtle : .clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlightedIndex = index } }
        .accessibilityLabel(Text(verbatim: "\(option.title)、\(option.explanation)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        guard !options.isEmpty else { return .handled }
        highlightedIndex = max(0, min(options.count - 1, highlightedIndex + delta))
        return .handled
    }
}
