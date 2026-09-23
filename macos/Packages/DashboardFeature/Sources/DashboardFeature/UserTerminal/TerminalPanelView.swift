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
                    coordinator?.feed(Data("\r\n[ターミナルの表示サイズを更新できませんでした]\r\n".utf8))
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

    /// 初回表示と、自然終了したシェルを再び表示するときにだけ起動する。
    public func ensureStarted() async {
        do {
            try await controller.ensureStarted()
        } catch {
            terminalCoordinator.feed(Data("\r\n[シェルを開始できませんでした]\r\n".utf8))
        }
    }

    deinit {
        outputTask?.cancel()
    }
}

/// ターミナルの子タブ・共通ターミナルに埋め込む、実シェルの SwiftTerm 表示。見出しはタブが兼ねる。
public struct TerminalPanelView: View {
    public let panel: TerminalPanelSession

    public init(panel: TerminalPanelSession) {
        self.panel = panel
    }

    public var body: some View {
        TerminalView(coordinator: panel.terminalCoordinator)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(DSColor.background)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("ターミナル")
            .accessibilityIdentifier("user-terminal-panel")
            .task {
                await panel.ensureStarted()
            }
    }
}
