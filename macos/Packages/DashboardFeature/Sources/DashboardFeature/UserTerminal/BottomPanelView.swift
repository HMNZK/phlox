import AppKit
import AgentDomain
import DesignSystem
import SwiftUI
import TerminalUI

/// 開閉の観測と高さの変更を中央の内容から分離する。
struct BottomPanelContainer<Content: View>: View {
    let state: BottomPanelState
    let project: Project?
    let terminals: ProjectTerminalStore?
    let content: Content

    init(state: BottomPanelState, project: Project?, terminals: ProjectTerminalStore?, @ViewBuilder content: () -> Content) {
        self.state = state
        self.project = project
        self.terminals = terminals
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            // タブ列より下の本文。使用量バーは親の safeAreaInset に置かれる。
            let availableHeight = geometry.size.height
            let height = BottomPanelLayout.clamped(state.preferredHeight, availableHeight: availableHeight)
            VStack(spacing: 0) {
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                if state.isVisible, let project, let terminals {
                    BottomPanelProjectView(state: state, project: project, terminals: terminals)
                        .id(project.id)
                        .frame(height: height)
                        .overlay(alignment: .top) {
                            BottomPanelHeightGrip(state: state, availableHeight: availableHeight, height: height)
                        }
                }
            }
            .frame(height: availableHeight, alignment: .top)
        }
    }
}

private struct BottomPanelProjectView: View {
    let state: BottomPanelState
    let project: Project
    let terminals: ProjectTerminalStore
    @State private var panel: TerminalPanelSession?
    @State private var loadedProjectID: ProjectID?

    var body: some View {
        Group {
            if let panel, loadedProjectID == project.id {
                BottomPanelView(panel: panel, state: state)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text("シェルを起動しています…"))
                    .accessibilityIdentifier("bottom-panel-loading")
            }
        }
        .task(id: project.directoryPath) {
            let session = terminals.bottomTerminal(for: project.id, workingDirectory: project.directoryPath)
            loadedProjectID = project.id
            panel = session
        }
    }
}

struct BottomPanelView: View {
    let panel: TerminalPanelSession
    let state: BottomPanelState
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 0) {
                TerminalPanelView(panel: panel, showsHeader: false, startsAutomatically: false, onFocusChange: { focused in
                    // AppKit の responder 更新中に SwiftUI の状態を書き換えない。
                    Task { @MainActor in state.isTerminalFocused = focused && state.isVisible }
                })
                    .accessibilityLabel(text("下部パネル、ターミナル"))
                    .overlay {
                        if !panel.controller.hasStarted, panel.controller.startError == nil {
                            ProgressView { text("シェルを起動しています…") }
                                .font(DSFont.auxiliary)
                        }
                    }
                if let startupError = panel.controller.startError {
                    Text(verbatim: startupError).font(DSFont.meta).foregroundStyle(DSColor.textPrimary)
                        .padding(DSSpacing.s).textSelection(.enabled)
                } else if panel.controller.hasStarted, !panel.controller.isRunning, !panel.controller.startInProgress {
                    HStack(spacing: DSSpacing.s) {
                        Text(verbatim: panel.controller.exitCode.map {
                            String(format: localized("シェルは終了しました（終了コード %lld）"), Int($0))
                        } ?? localized("シェルは終了しました"))
                            .font(DSFont.auxiliary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { restart() } label: {
                            text("再起動").font(DSFont.auxiliary)
                                .foregroundStyle(DSColor.terminalControlForeground)
                                .padding(.horizontal, DSSpacing.m)
                                .frame(height: DSLayout.controlChipHeight - DSSpacing.xs)
                                .background(DSColor.terminalControlBackground, in: RoundedRectangle(cornerRadius: DSRadius.row))
                                .overlay { RoundedRectangle(cornerRadius: DSRadius.row).strokeBorder(DSColor.terminalControlBorder, lineWidth: DSLayout.controlBorderWidth) }
                        }
                            .buttonStyle(HoverableIconButtonStyle())
                            .accessibilityIdentifier("bottom-panel-exited-restart")
                            .accessibilityLabel(text("シェルを再起動"))
                    }
                    .foregroundStyle(DSColor.terminalStatusText)
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.vertical, DSSpacing.s)
                    .frame(maxWidth: .infinity)
                    .background(DSColor.terminalBackground)
                    .overlay(alignment: .top) { Rectangle().fill(DSColor.separator).frame(height: DSLayout.paneSeparatorWidth) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.m)
                    .inset(by: -(DSLayout.focusRingGap + DSLayout.focusRingWidth))
                    .strokeBorder(state.isTerminalFocused ? DSColor.focusRing : .clear, lineWidth: DSLayout.focusRingWidth)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, DSSpacing.s)
            .padding(.bottom, DSSpacing.s)
        }
        .background(DSColor.panelBackground)
        .overlay(alignment: .top) { Rectangle().fill(DSColor.separator).frame(height: DSLayout.paneSeparatorWidth) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text("下部パネル"))
        .accessibilityIdentifier("bottom-panel")
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusTerminal()
            await panel.ensureBottomStarted()
        }
        .onChange(of: state.focusRequest) { _, _ in focusTerminal() }
        .onDisappear {
            state.isTerminalFocused = false
        }
    }

    private var header: some View {
        HStack(spacing: DSSpacing.chip) {
            text("下部パネル")
                .font(DSFont.auxiliary.weight(state.isTerminalFocused ? .semibold : .medium))
                .foregroundStyle(state.isTerminalFocused ? DSColor.textPrimary : DSColor.textSecondary)
                .fixedSize()
            Text(verbatim: "·").font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: (panel.controller.shellPath as NSString).lastPathComponent)
                .font(DSFont.monoCaption).foregroundStyle(DSColor.textSecondary).fixedSize()
            if panel.controller.hasStarted, !panel.controller.isRunning, !panel.controller.startInProgress {
                Text(verbatim: "·").font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
                text("シェル終了").font(DSFont.meta).foregroundStyle(DSColor.textSecondary).fixedSize()
            }
            Text(verbatim: "·").font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
            Text(verbatim: (panel.controller.workingDirectory as NSString).abbreviatingWithTildeInPath)
                .font(DSFont.monoCaption).foregroundStyle(DSColor.textSecondary)
                .lineLimit(1).truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(panel.controller.workingDirectory)
            if let path = panel.controller.shellResolution?.unavailablePath {
                Label {
                    text("設定のシェルが見つかりません").lineLimit(1).truncationMode(.tail)
                } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(DSFont.meta).foregroundStyle(DSColor.textPrimary)
                    .layoutPriority(-1)
                    .help(Text(verbatim: String(format: localized("設定のシェル（%@）が見つからないため、システムの既定で起動しました"), path)))
                    .accessibilityIdentifier("bottom-panel-shell-warning")
            }
            iconButton("arrow.clockwise", label: "シェルを再起動", identifier: "bottom-panel-restart", action: restart)
                .fixedSize().layoutPriority(1)
                .disabled(panel.controller.startInProgress)
            iconButton("chevron.down", label: "パネルを閉じる", identifier: "bottom-panel-close") { state.close() }
                .fixedSize().layoutPriority(1)
        }
        .padding(.leading, DSSpacing.m)
        .padding(.trailing, DSSpacing.chip)
        .frame(height: DSLayout.bottomPanelHeaderHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: headerAccessibilityLabel))
        .accessibilityIdentifier("bottom-panel-header")
    }

    var headerAccessibilityLabel: String {
        Self.headerAccessibilityLabel(shellPath: panel.controller.shellPath,
            workingDirectory: panel.controller.workingDirectory, focused: state.isTerminalFocused,
            locale: locale, bundle: localizationBundle)
    }

    static func headerAccessibilityLabel(shellPath: String, workingDirectory: String, focused: Bool,
                                         locale: Locale, bundle: Bundle = .main) -> String {
        let shell = (shellPath as NSString).lastPathComponent
        let place = (workingDirectory as NSString).abbreviatingWithTildeInPath
        let input = AppLocalizedString.string(focused ? "入力中" : "キー入力なし", locale: locale, bundle: bundle)
        return String(format: AppLocalizedString.string("下部パネル、ターミナル、%@、%@、%@", locale: locale, bundle: bundle), shell, place, input)
    }

    private func iconButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(DSFont.auxiliary)
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: DSLayout.bottomPanelButtonWidth, height: DSLayout.controlChipHeight - DSSpacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(text(label)).accessibilityLabel(text(label)).accessibilityIdentifier(identifier)
    }

    private func restart() {
        Task { @MainActor in
            await panel.restart()
            focusTerminal()
        }
    }

    private func focusTerminal() {
        let view = panel.terminalCoordinator.terminalView
        view.window?.makeFirstResponder(view)
    }

    private func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: localizationBundle) }
    private func text(_ key: String) -> Text { Text(verbatim: localized(key)) }
}

/// ドラッグ中はこの小さなビューの予告線だけが変わり、会話・グリッドの高さは確定まで固定。
private struct BottomPanelHeightGrip: View {
    let state: BottomPanelState
    let availableHeight: CGFloat
    let height: CGFloat
    @State private var translation: CGFloat = 0
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    var body: some View {
        Rectangle().fill(DSColor.separator)
            .frame(height: DSLayout.paneSeparatorWidth)
            .frame(height: DSLayout.dividerHitWidth)
            .contentShape(Rectangle())
            .overlay {
                if hovering || focused || translation != 0 {
                    Rectangle().fill(DSColor.focusRing).frame(height: DSLayout.focusRingWidth + DSLayout.paneSeparatorWidth)
                        .offset(y: translation).allowsHitTesting(false)
                }
            }
            .onHover { inside in
                if inside && !hovering { NSCursor.resizeUpDown.push() }
                if !inside && hovering { NSCursor.pop() }
                hovering = inside
            }
            .onDisappear { if hovering { NSCursor.pop() } }
            .gesture(DragGesture().onChanged { value in
                translation = height - BottomPanelLayout.clamped(height - value.translation.height, availableHeight: availableHeight)
            }.onEnded { value in
                state.saveHeight(height - value.translation.height, availableHeight: availableHeight)
                translation = 0
            })
            .focusable().focused($focused)
            .onKeyPress(.upArrow) { adjust(by: DSSpacing.l); return .handled }
            .onKeyPress(.downArrow) { adjust(by: -DSSpacing.l); return .handled }
            .accessibilityElement()
            .accessibilityLabel(Text("下部パネルの高さ"))
            .accessibilityValue(Text(verbatim: String(format: AppLocalizedString.string("%lldポイント", locale: locale, bundle: localizationBundle), Int(height))))
            .accessibilityIdentifier("bottom-panel-height")
            .accessibilityAdjustableAction { direction in adjust(by: direction == .increment ? DSSpacing.l : -DSSpacing.l) }
    }

    private func adjust(by delta: CGFloat) { state.saveHeight(height + delta, availableHeight: availableHeight) }
}
