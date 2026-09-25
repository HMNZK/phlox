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
    enum Key { case up, down, left, right, confirm }
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
    /// ←→ も箱へ渡す（2 列の箱で列を移る）。ほかの箱では入力欄のカーソル移動に残す。
    var relaysHorizontalKeys = false
    @ViewBuilder let popup: () -> Popup
    @State private var anchorFrame: CGRect = .zero
    @State private var popupFrame: CGRect = .zero
    /// 箱の外へはみ出して描く部分（2 列の子の箱）。外のクリックの判定に含める。
    @State private var overhangFrame: CGRect = .zero
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
                        .onPreferenceChange(ComposerPopupOverhangKey.self) { overhangFrame = $0 }
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
            if !popupFrame.contains(point) && !overhangFrame.contains(point) && !anchorFrame.contains(point) {
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
        case 123 where relaysHorizontalKeys: key = .left
        case 124 where relaysHorizontalKeys: key = .right
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

/// 箱の外へはみ出して描く部分の位置（global）。
struct ComposerPopupOverhangKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = value.union(nextValue()) }
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
        relaysHorizontalKeys: Bool = false,
        @ViewBuilder popup: @escaping () -> Popup
    ) -> some View {
        modifier(ComposerPopupPresenter(
            isPresented: isPresented,
            alignment: alignment,
            gap: gap,
            relaysHorizontalKeys: relaysHorizontalKeys,
            popup: popup
        ))
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
    /// 2 列の箱で、いま ↑↓↩ を受ける列か。受けない列は指している行を出さない。
    var handlesKeys = true
    /// ポインタが行に乗ったとき（2 列の箱で、その列へ移る）。
    var onHoverRow: (() -> Void)? = nil
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
                    .font(DSFont.meta.weight(.semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
            if let search {
                TextField(text: search) { Text(verbatim: searchPlaceholder) }
                    .textFieldStyle(.plain)
                    .font(DSFont.auxiliary)
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
                        .font(DSFont.meta.weight(.semibold))
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
            guard handlesKeys else { return }
            switch event?.key {
            case .up?: _ = move(-1)
            case .down?: _ = move(1)
            case .confirm?: _ = activateHighlighted()
            case .left?, .right?, nil: break
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
        let isHighlighted = handlesKeys && row.isEnabled && highlightedID == row.id
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
                        .font(DSFont.meta)
                        .opacity(0.75)
                }
            }
            .font(DSFont.row)
            .foregroundStyle(isHighlighted ? Color.white : (row.isEnabled ? DSColor.textPrimary : DSColor.textTertiary))
            .padding(.horizontal, 10)
            .frame(height: rowHeight)
            .background(isHighlighted ? DSColor.accentFill : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.isEnabled)
        .onHover {
            guard $0 && row.isEnabled else { return }
            highlightedID = row.id
            onHoverRow?()
        }
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
        handlesKeys: Bool = true,
        onHoverRow: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.init(
            header: header,
            search: search,
            searchPlaceholder: searchPlaceholder,
            sections: sections,
            rowHeight: rowHeight,
            monospacedRows: monospacedRows,
            handlesKeys: handlesKeys,
            onHoverRow: onHoverRow,
            onClose: onClose,
            footer: { EmptyView() }
        )
    }
}

/// 横に子の箱を出す 2 列の選択（PhloxReply.dc.html の effortSub: 親 260・子 150、子は親の右端から 4 内側・上から 30）。
/// 子の箱は親の箱に重ねて描き、親の位置（チップの真上）を動かさない。
/// ←→ で列を移り（移った列の名前を読み上げる）、↑↓↩ はいまの列が受ける。ポインタを乗せた列へも移る。
struct ComposerMenuWithSideList: View {
    let title: String
    let sections: [ComposerMenuSection]
    let sideTitle: String
    let sideSection: ComposerMenuSection?
    let onClose: () -> Void
    @State private var isSideActive = false
    @Environment(\.composerPopupKey) private var popupKey

    private static let width: CGFloat = 260

    var body: some View {
        ComposerPopupSurface(width: Self.width) {
            ComposerMenuList(
                sections: sections,
                handlesKeys: !isSideActive,
                onHoverRow: { isSideActive = false },
                onClose: onClose
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: title))
        .overlay(alignment: .topLeading) {
            if let sideSection {
                ComposerPopupSurface(width: 150) {
                    ComposerMenuList(
                        header: sideTitle,
                        sections: [sideSection],
                        handlesKeys: isSideActive,
                        onHoverRow: { isSideActive = true },
                        onClose: onClose
                    )
                }
                .fixedSize()
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ComposerPopupOverhangKey.self, value: proxy.frame(in: .global))
                })
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(verbatim: sideTitle))
                .padding(.leading, Self.width - 4)
                .padding(.top, 30)
            }
        }
        .onChange(of: popupKey) { _, event in
            switch event?.key {
            case .left?: setSideActive(false)
            case .right?: setSideActive(sideSection != nil)
            default: break
            }
        }
    }

    private func setSideActive(_ active: Bool) {
        guard active != isSideActive else { return }
        isSideActive = active
        AccessibilityNotification.Announcement(active ? sideTitle : title).post()
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
                    .font(DSFont.row.weight(.semibold))
                Text(verbatim: subtitle)
                    .font(DSFont.meta)
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
                        .font(DSFont.dense.weight(.medium))
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
                .font(DSFont.meta)
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
            case .left?, .right?, nil: break
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
                        .font(DSFont.dense.weight(.medium))
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
