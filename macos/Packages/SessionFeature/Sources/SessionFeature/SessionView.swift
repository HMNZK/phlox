import SwiftUI
import AgentDomain
import TerminalUI
import DesignSystem

public struct SessionView: View {
    @Bindable var viewModel: SessionViewModel
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    public init(viewModel: SessionViewModel) {
        _viewModel = Bindable(wrappedValue: viewModel)
    }

    /// 04 D3: 会話型と同じ 56pt のヘッダ（題名 / 「エージェント · ターミナル · 作業フォルダ · ブランチ」/ 状態）。
    /// 端末の面はテーマによらず濃色で、周りに 12/16 の余白（PhloxChat.dc.html の isPty）。
    public var body: some View {
        let _ = themeID
        VStack(alignment: .leading, spacing: 0) {
            TerminalSessionHeader(viewModel: viewModel)
            TerminalView(coordinator: viewModel.terminalCoordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Self.terminalBackground)
        }
        .background(DSColor.background)
    }

    /// 端末に当てている配色の背景（余白を同じ色で塗って継ぎ目を出さない）。
    private static var terminalBackground: Color {
        let c = TerminalCoordinator.activePalette.background
        return Color(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
}

private struct TerminalSessionHeader: View {
    @Bindable var viewModel: SessionViewModel
    @State private var branch: String?
    @Environment(\.locale) private var locale
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        let presentation = SessionTitlePresentation(
            state: viewModel.titleState,
            fallback: SessionViewModel.shortID(for: viewModel.id),
            workspacePath: viewModel.workspacePath
        )
        let displayState = SessionDisplayState.resolve(viewModel.status, hasUnseenCompletion: viewModel.hasUnseenCompletion)
        HStack(spacing: DSSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: presentation.primary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(presentation.helpText)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 7) {
                    Text(verbatim: agentName).fixedSize()
                    dot
                    Text("ターミナル").fixedSize()
                    if !viewModel.workspacePath.isEmpty {
                        dot
                        Text(verbatim: viewModel.workspacePath)
                            .font(.system(size: 11, design: .monospaced))
                            .truncationMode(.middle)
                    }
                    if let branch {
                        dot
                        Text(verbatim: branch)
                            .font(.system(size: 11, design: .monospaced))
                            .fixedSize()
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let kind = displayState.attentionKind {
                Text(verbatim: displayState.localizedLabel(locale: locale))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DSColor.attentionInk(kind))
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(DSColor.attentionTint(kind), in: RoundedRectangle(cornerRadius: 6))
                    .fixedSize()
            } else {
                Text(verbatim: displayState.localizedLabel(locale: locale))
                    .font(.system(size: 12, weight: displayState == .running ? .medium : .regular))
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize()
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, DSSpacing.l)
        .frame(height: 56)
        .background(DSColor.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DSColor.separator).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("セッションヘッダ"))
        .task(id: viewModel.rawWorkspacePath) {
            let path = viewModel.rawWorkspacePath
            while !Task.isCancelled {
                let current = GitBranchReader.currentBranch(at: path)
                if current != branch { branch = current }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// 「aider（カスタム）」。組み込みのエージェントは名前だけ。
    private var agentName: String {
        let name = viewModel.agentDescriptor.displayName
        if case .custom = viewModel.agentRef {
            return String(format: AppLocalizedString.string("%@（カスタム）", locale: locale), name)
        }
        return name
    }

    private var dot: some View {
        Text(verbatim: "·").foregroundStyle(DSColor.textTertiary)
    }
}
