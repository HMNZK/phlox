import AppKit
import Foundation
import SwiftUI
import DesignSystem
import TerminalUI

/// ユーザー用シェルと SwiftTerm 表示器を結びつける、パネル容器から独立した寿命の所有者。
/// タブを切り替えてもここが保持されるため、PTY は終了しない。
@MainActor
public final class TerminalPanelSession {
    public let controller: UserTerminalController
    public let terminalCoordinator: TerminalCoordinator

    private var outputTask: Task<Void, Never>?

    public init(controller: UserTerminalController) {
        self.controller = controller
        let coordinator = TerminalCoordinator()
        coordinator.applyFontSize(TerminalFontSettings.currentSize())
        self.terminalCoordinator = coordinator

        coordinator.onInput = { [weak controller, weak coordinator] data in
            let input = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                guard let controller else { return }
                do {
                    try await controller.send(input)
                } catch {
                    coordinator?.feed(Data("\r\n[ターミナル入力を送信できませんでした]\r\n".utf8))
                }
            }
        }

        coordinator.onResize = { [weak controller, weak coordinator] cols, rows in
            Task { @MainActor in
                guard let controller else { return }
                do {
                    try await controller.resize(cols: cols, rows: rows)
                } catch {
                    // 07 D7: 赤（#FF8A8D）の 1 行。端末は常に暗い面なので色は固定。
                    let message = String(format: AppLocalizedString.string("[Phlox] シェルのサイズ変更に失敗しました（%@）。", locale: TerminalPanelSession.displayLocale), error.localizedDescription)
                    coordinator?.feed(Data("\r\n\u{1B}[38;2;255;138;141m\(message)\u{1B}[0m\r\n".utf8))
                }
            }
        }

        // 表示容器が閉じていても購読を続ける。Coordinator が SwiftTerm のバッファを
        // 保持するため、再アタッチ時に過去の画面が空白にならない。シェルの起動は
        // 初めて表示器が現れたときまで遅延し、使われない常駐シェルを作らない。
        outputTask = Task { [weak controller, weak coordinator] in
            guard let controller, let coordinator else { return }
            let output = controller.makeOutputStream()
            for await data in output {
                guard !Task.isCancelled else { return }
                coordinator.feed(data)
            }
        }
    }

    /// 端末に流す文言の表示言語（App の `LanguageSettings` と同じキー。未設定・"system" は OS に従う）。
    static var displayLocale: Locale {
        guard let code = UserDefaults.standard.string(forKey: "phlox.appLanguage"), code != "system" else { return .autoupdatingCurrent }
        return Locale(identifier: code)
    }

    /// 初回表示と、自然終了したシェルを再び表示するときにだけ起動する。
    public func ensureStarted() async {
        do {
            try await controller.ensureStarted()
        } catch {
            terminalCoordinator.feed(Data("\r\n[シェルを開始できませんでした]\r\n".utf8))
        }
    }

    /// 見出しの「再起動」。
    public func restart() async {
        do {
            try await controller.restart()
        } catch {
            terminalCoordinator.feed(Data("\r\n[シェルを開始できませんでした]\r\n".utf8))
        }
    }

    deinit {
        outputTask?.cancel()
    }
}

/// ⌘+ / ⌘− と同じ経路で端末の文字サイズを変える（見出しの A− / A+）。DashboardView が入れる。
extension EnvironmentValues {
    @Entry var adjustTerminalFontSize: ((CGFloat) -> Void)? = nil
}

/// ターミナルの子タブ・共通ターミナルに埋め込む、実シェルの SwiftTerm 表示（07 D1・D8）。
/// 見出しに「ターミナル · シェル · 場所」と文字サイズ（A− / A+）。文字サイズが変わると中央に 1 秒だけ大きさを出す。
public struct TerminalPanelView: View {
    public let panel: TerminalPanelSession
    /// グリッドのタイルではタイルの見出しがあるので出さない。
    let showsHeader: Bool
    /// 文字サイズを変えたときの中央の表示（07 D8）。グリッドのタイルでは全タイルに一斉に出るので出さない。
    let showsFontSizeHUD: Bool
    /// グリッドのタイルの子タブ。端末の文字をグリッドの大きさ（06: 単体の 11/11.5）で描く。
    let isInGridTile: Bool

    @AppStorage(TerminalFontSettings.fontSizeKey) private var fontSize = Double(NSFont.systemFontSize)
    @Environment(\.adjustTerminalFontSize) private var adjustFontSize
    @State private var hudVisibleUntil: Date?

    public init(panel: TerminalPanelSession, showsHeader: Bool = true, showsFontSizeHUD: Bool = true, isInGridTile: Bool = false) {
        self.panel = panel
        self.showsHeader = showsHeader
        self.showsFontSizeHUD = showsFontSizeHUD
        self.isInGridTile = isInGridTile
    }

    /// 同じ端末が単体とグリッドの両方に出るので、出るたびにその場の大きさへ当て直す。
    private func applyFontSize(_ size: CGFloat) {
        panel.terminalCoordinator.applyFontSize(isInGridTile ? TerminalFontSettings.gridSize(size) : size)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
            }
            TerminalView(coordinator: panel.terminalCoordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay { fontSizeHUD }
        }
        .background(DSColor.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ターミナル")
        .accessibilityIdentifier("user-terminal-panel")
        .task {
            await panel.ensureStarted()
        }
        .onAppear { applyFontSize(CGFloat(fontSize)) }
        .onChange(of: fontSize) { _, newValue in
            applyFontSize(CGFloat(newValue))
            guard showsFontSizeHUD else { return }
            let until = Date().addingTimeInterval(1)
            hudVisibleUntil = until
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if hudVisibleUntil == until { hudVisibleUntil = nil }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("ターミナル")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
            Text(verbatim: subtitle)
                .font(.system(size: 11))
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            fontButton("A−", delta: -1, label: "文字を小さく（⌘−）")
                .disabled(CGFloat(fontSize) <= TerminalFontSettings.minSize)
            Text(verbatim: "\(Int(fontSize))pt")
                .font(.system(size: 10.5))
                .foregroundStyle(DSColor.textTertiary)
                .monospacedDigit()
                .accessibilityHidden(true)
            fontButton("A+", delta: 1, label: "文字を大きく（⌘+）")
                .disabled(CGFloat(fontSize) >= TerminalFontSettings.maxSize)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 32)
        .background(DSColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DSColor.separator).frame(height: 1)
        }
    }

    /// 「zsh · ~/dev/phlox」。
    private var subtitle: String {
        let shell = (panel.controller.shellPath as NSString).lastPathComponent
        let place = (panel.controller.workingDirectory as NSString).abbreviatingWithTildeInPath
        return "\(shell) · \(place)"
    }

    private func fontButton(_ title: String, delta: CGFloat, label: LocalizedStringKey) -> some View {
        Button {
            if let adjustFontSize {
                adjustFontSize(delta)
            } else {
                TerminalFontSettings.save(TerminalFontSettings.adjusted(from: CGFloat(fontSize), by: delta))
            }
        } label: {
            Text(verbatim: title)
                .font(.system(size: delta > 0 ? 12 : 11))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private var fontSizeHUD: some View {
        if hudVisibleUntil != nil {
            Text(verbatim: String(format: AppLocalizedString.string("ターミナル %lldpt", locale: locale), Int(fontSize)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(white: 0.12, opacity: 0.88), in: RoundedRectangle(cornerRadius: 10))
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    @Environment(\.locale) private var locale
}
