import Foundation
import SwiftUI
import DesignSystem

/// ゲート②で撤去または昇格する、独立ウィンドウ容器だけのプロトタイプ。
/// 通常は false（Dashboard 内ドロワー）。起動前にこの UserDefaults を true にすると
/// ⌘⌥T が Window scene を前面へ出す方式を比較できる。
public enum PanelContainerPrototype {
    public static let windowModeDefaultsKey = "phlox.terminalPanel.prototype.windowMode"
    public static let windowID = "user-terminal-window"

    public static var usesSeparateWindow: Bool {
        UserDefaults.standard.bool(forKey: windowModeDefaultsKey)
    }

    /// ドロワーを実体化するのは、パネルが開いていて Window 方式を選んでいないときだけ。
    /// 方式判定を Dashboard へ漏らさず、プロトタイプの撤去範囲をここへ閉じ込める。
    public static func isDrawerActive(visible: Bool) -> Bool {
        visible && !usesSeparateWindow
    }

    public static func drawerReservation(visible: Bool, preferredWidth: CGFloat) -> CGFloat {
        isDrawerActive(visible: visible) ? preferredWidth + 1 : 0
    }

    /// 比較用 Window scene の定義をプロトタイプに閉じ込める。
    @MainActor
    public static func windowScene(
        panel: TerminalPanelSession?,
        router: AppRouter?,
        preferredColorScheme: ColorScheme?,
        locale: Locale
    ) -> some Scene {
        Window("ターミナル", id: windowID) {
            TerminalPanelPrototypeWindowView(panel: panel, router: router)
                .preferredColorScheme(preferredColorScheme)
                .environment(\.locale, locale)
        }
        .defaultSize(width: 720, height: 460)
    }

    /// Window 方式だけ比較用 scene を開く。通常のトグル配線は App 側に残す。
    @MainActor
    public static func openWindowIfNeeded(router: AppRouter?, openWindow: (String) -> Void) {
        guard let router else { return }
        guard router.terminalPanelVisible, usesSeparateWindow else { return }
        openWindow(windowID)
    }
}

/// `Window(id:)` に載せるための容器。シェルと表示状態は所有せず、App が渡す共有 session を使う。
public struct TerminalPanelPrototypeWindowView: View {
    public let panel: TerminalPanelSession?
    public let router: AppRouter?
    @Environment(\.dismiss) private var dismiss

    public init(panel: TerminalPanelSession?, router: AppRouter?) {
        self.panel = panel
        self.router = router
    }

    public var body: some View {
        Group {
            // ドロワー方式で Window scene がメニュー等から開かれても、同じ AppKit view を
            // 二重にマウントしない。比較用 Window はこの方式が選択された時だけ実体を持つ。
            if PanelContainerPrototype.usesSeparateWindow,
               let panel,
               router?.terminalPanelVisible == true {
                TerminalPanelView(panel: panel)
            } else {
                ContentUnavailableView(
                    "ターミナルは閉じています",
                    systemImage: "terminal",
                    description: Text("⌘⌥T で開きます")
                )
                .foregroundStyle(DSColor.textSecondary)
            }
        }
        .background(DSColor.background)
        .onChange(of: router?.terminalPanelVisible) { _, isVisible in
            if isVisible != true {
                dismiss()
            }
        }
    }
}
