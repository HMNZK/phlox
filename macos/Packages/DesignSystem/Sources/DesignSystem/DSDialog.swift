#if os(macOS)
import AppKit
import SwiftUI

/// 09 Dialogs の確認・お知らせ。標準のアラートでは既定ボタンの色・ボタンの左右・キー表記・アイコンを
/// 変えられないため、同じ中身を自前で描く。ウィンドウ内の対象は `.dsDialog` のシート、
/// ビューの外（保存パネルの後など）は `DSDialogModal.run` の独立したパネルで出す。
///
/// 型: A 取り返しがつかない（注意バッジ・キャンセルが既定・破壊ボタンは赤い文字で ⌘⌫）、
/// B 取り返せる（アプリアイコンだけ・実行が既定）、C お知らせ（注意バッジ・OK が既定）。
/// どの型も Esc でキャンセル（`onCancel`）。
public struct DSDialog<Detail: View>: View {
    public enum Kind: Sendable {
        case irreversible
        case recoverable
        case notice
    }

    let kind: Kind
    let title: String
    let message: String?
    let note: String?
    let buttons: [DSDialogButton]
    let onCancel: () -> Void
    let detail: Detail
    @Environment(\.locale) private var locale

    public init(
        _ kind: Kind,
        title: String,
        message: String? = nil,
        note: String? = nil,
        buttons: [DSDialogButton],
        onCancel: @escaping () -> Void,
        @ViewBuilder detail: () -> Detail
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.note = note
        self.buttons = buttons
        self.onCancel = onCancel
        self.detail = detail()
    }

    public var body: some View {
        VStack(spacing: 10) {
            AppIconBadge(showsCaution: kind != .recoverable, size: 56)
            Text(verbatim: title)
                .font(DSFont.row.weight(.bold))
                .lineSpacing(3)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(verbatim: message)
                    .font(.system(size: 11.5))
                    .lineSpacing(4)
                    .foregroundStyle(DSColor.textPrimary)
            }
            detail
            if let note {
                Text(verbatim: note)
                    .font(DSFont.meta)
                    .lineSpacing(3)
                    .foregroundStyle(DSColor.textSecondary)
            }
            buttonRow
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(EdgeInsets(top: 20, leading: 16, bottom: 16, trailing: 16))
        .frame(width: 300)
        .background(DSColor.dialogBackground)
        .onExitCommand(perform: onCancel)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// ボタンが 3 つ以上か、どれかの名前が 8 文字を超えるときは縦に並べる（09）。
    @ViewBuilder
    private var buttonRow: some View {
        let stacked = buttons.count >= 3 || buttons.contains { AppLocalizedString.string($0.title, locale: locale).count > 8 }
        if stacked {
            VStack(spacing: 8) { buttonViews }
        } else {
            HStack(spacing: 8) { buttonViews }
        }
    }

    private var buttonViews: some View {
        ForEach(buttons) { button in
            switch button.role {
            case .primary:
                Button(LocalizedStringKey(button.title), action: button.action)
                    .buttonStyle(.ds(.primary, keyHint: "↩", fillsWidth: true))
                    .keyboardShortcut(.defaultAction)
            case .destructive:
                Button(LocalizedStringKey(button.title), action: button.action)
                    .buttonStyle(.ds(.destructive, keyHint: "⌘⌫", fillsWidth: true))
                    .keyboardShortcut(.delete, modifiers: .command)
            case .normal:
                Button(LocalizedStringKey(button.title), action: button.action)
                    .buttonStyle(.ds(.secondary, fillsWidth: true))
            }
        }
    }
}

public extension DSDialog where Detail == EmptyView {
    init(
        _ kind: Kind,
        title: String,
        message: String? = nil,
        note: String? = nil,
        buttons: [DSDialogButton],
        onCancel: @escaping () -> Void
    ) {
        self.init(kind, title: title, message: message, note: note, buttons: buttons, onCancel: onCancel) { EmptyView() }
    }
}

/// ダイアログのボタン。`title` は Localizable.xcstrings のキー（日本語）。
/// 主（accent の面・↩）、破壊（赤い文字・⌘⌫）、ふつう（操作面）。並びは配列の順（横なら左から、縦なら上から）。
public struct DSDialogButton: Identifiable {
    public enum Role: Sendable {
        case normal
        case primary
        case destructive
    }

    public let id: String
    let title: String
    let role: Role
    let action: () -> Void

    public init(_ title: String, role: Role = .normal, action: @escaping () -> Void) {
        self.id = title
        self.title = title
        self.role = role
        self.action = action
    }
}

/// 巻き込まれるものの一覧（09 D3 の子セッション）。行の高さ 26・右に 10.5pt の補足。
public struct DSDialogList: View {
    public struct Row: Identifiable, Hashable {
        public let id: Int
        public let title: String
        public let meta: String

        public init(id: Int, title: String, meta: String) {
            self.id = id
            self.title = title
            self.meta = meta
        }
    }

    let rows: [Row]

    public init(rows: [Row]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(verbatim: row.title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: row.meta)
                        .font(.system(size: 10.5))
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .overlay(alignment: .top) {
                    if row.id != rows.first?.id {
                        Rectangle().fill(DSColor.separator).frame(height: 1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DSColor.separator, lineWidth: 1))
    }
}

/// 原因の文（エラー・git の出力）をそのまま等幅で出す（09 D1・D2・D10・E4）。
public struct DSDialogLog: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        ScrollView {
            Text(verbatim: text)
                .font(.system(size: 10.5, design: .monospaced))
                .lineSpacing(4)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
        }
        .frame(maxHeight: 120)
        .fixedSize(horizontal: false, vertical: true)
        .background(DSColor.codeBackground, in: RoundedRectangle(cornerRadius: 6))
    }
}

public extension View {
    /// ウィンドウに付くシートで `DSDialog` を出す。表示言語はシートの外と同じにする。
    func dsDialog<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(DSDialogItemPresenter(item: item, dialog: content))
    }

    func dsDialog<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(DSDialogFlagPresenter(isPresented: isPresented, dialog: content))
    }
}

private struct DSDialogItemPresenter<Item: Identifiable, Dialog: View>: ViewModifier {
    @Binding var item: Item?
    let dialog: (Item) -> Dialog
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.sheet(item: $item) { item in
            dialog(item).environment(\.locale, locale)
        }
    }
}

private struct DSDialogFlagPresenter<Dialog: View>: ViewModifier {
    @Binding var isPresented: Bool
    let dialog: () -> Dialog
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            dialog().environment(\.locale, locale)
        }
    }
}

/// ビューの外から出すお知らせ（09 D10 の書き込み失敗など）。独立したパネルでアプリをモーダルにし、
/// 押したボタンの番号（`buttons` の添字。Esc は nil）を返す。
@MainActor
public enum DSDialogModal {
    public static func run(
        _ kind: DSDialog<AnyView>.Kind,
        title: String,
        message: String? = nil,
        log: String? = nil,
        content: AnyView? = nil,
        buttons: [(title: String, role: DSDialogButton.Role)],
        locale: Locale
    ) -> Int? {
        var chosen: Int?
        let finish: (Int?) -> Void = { index in
            chosen = index
            NSApp.stopModal()
        }
        let dialog = DSDialog(
            kind,
            title: title,
            message: message,
            buttons: buttons.enumerated().map { index, button in
                DSDialogButton(button.title, role: button.role) { finish(index) }
            },
            onCancel: { finish(nil) }
        ) {
            content ?? AnyView(log.map { DSDialogLog($0) })
        }
        .environment(\.locale, locale)

        let hosting = NSHostingController(rootView: dialog)
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .fullSizeContentView]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.center()
        NSApp.runModal(for: panel)
        panel.close()
        return chosen
    }
}
#endif
