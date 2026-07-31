import Foundation
import SwiftUI
import DesignSystem
import TerminalUI

/// ユーザー用シェルと SwiftTerm 表示器を結びつける、パネル容器から独立した寿命の所有者。
/// ドロワーを閉じてもここは Dashboard / Window scene に保持されるため、PTY は終了しない。
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

/// ドロワー・独立ウィンドウのどちらにも埋め込める、実シェルの SwiftTerm 表示。
public struct TerminalPanelView: View {
    public let panel: TerminalPanelSession
    /// ドロワー内での最上段要素にだけ 28pt（最前面オーバーレイのトップバーと非衝突分）を
    /// 付ける。容器（DashboardView）側が積み位置に応じて渡す。
    private let topInset: CGFloat

    public init(panel: TerminalPanelSession, topInset: CGFloat = 28) {
        self.panel = panel
        self.topInset = topInset
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "terminal")
                    .foregroundStyle(DSColor.textSecondary)
                Text("ターミナル")
                    .font(DSFont.body.weight(.medium))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(DSColor.background)

            Rectangle()
                .fill(DSColor.separator)
                .frame(height: 1)

            TerminalView(coordinator: panel.terminalCoordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(DSColor.background)
        // 最前面オーバーレイのトップバー（32pt）と競合しない、既存 trailing pane と
        // 同じ上端インセット。TerminalView の AppKit NSView を操作系から離す。
        // ドロワー内で最上段でない（他パネルの下に積まれている）場合は容器が 0 を渡す。
        .padding(.top, topInset)
        .accessibilityIdentifier("user-terminal-panel")
        .task {
            await panel.ensureStarted()
        }
    }
}
