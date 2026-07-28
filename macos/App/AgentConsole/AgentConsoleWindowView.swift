import SwiftUI
import AppBootstrap
import AgentConfigKit
import DesignSystem

/// 「エージェント管理」ウィンドウ。Claude Code / Codex / Cursor の設定をここへ集める。
///
/// Claude Code の `/plugin` `/permissions` `/memory` などは対話 TUI 専用で、Phlox が使う
/// ヘッドレスのセッションには存在しない。Codex と Cursor も同様に、設定変更の入口が
/// 対話 TUI か設定ファイルの手編集しかない。どちらも「非対話のサブコマンド」と
/// 「設定ファイルの安全な部分更新」に置き換えたのがこの画面。
struct AgentConsoleWindowView: View {
    /// アプリ本体の初期化（composition）が終わるまで nil。ウィンドウ復元が先に走る経路があるため、
    /// View 側では「後から届く値」として扱い、届いたら model へ流し込んで読み直す。
    let claudeExecutablePath: String?
    let pathEnvironment: String
    let projectDirectory: URL?

    @State private var claude: ClaudeConsoleModel
    @State private var codex: CodexConsoleModel
    @State private var cursor: CursorConsoleModel
    /// 選択は Optional で持ち、表示時に既定へ倒す。
    @State private var selection: AgentConsoleSection? = .claudeStatus

    init(claudeExecutablePath: String?, pathEnvironment: String, projectDirectory: URL?) {
        self.claudeExecutablePath = claudeExecutablePath
        self.pathEnvironment = pathEnvironment
        self.projectDirectory = projectDirectory
        _claude = State(
            wrappedValue: ClaudeConsoleModel(
                claudeExecutablePath: claudeExecutablePath,
                pathEnvironment: pathEnvironment,
                projectDirectory: projectDirectory
            )
        )
        _codex = State(
            wrappedValue: CodexConsoleModel(
                executablePath: nil,
                pathEnvironment: pathEnvironment,
                projectDirectory: projectDirectory
            )
        )
        _cursor = State(
            wrappedValue: CursorConsoleModel(
                executablePath: nil,
                pathEnvironment: pathEnvironment
            )
        )
    }

    /// NavigationSplitView は列の境目に必ずシステムの区切り線を引き、サイドバーにも
    /// 独自の面を敷く。画面全体を1枚の板として見せたいので、素の HStack で組む
    /// （項目は固定数なので、列の折りたたみ・リサイズは要らない）。
    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 232)

            VStack(spacing: 0) {
                messageBar
                detail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(DSColor.background)
        .tint(DSColor.accent)
        .toggleStyle(AccentSwitchToggleStyle())
        // composition 完了で claudeExecutablePath が nil → 実パスへ変わるので、その都度読み直す。
        .task(id: claudeExecutablePath) { await reload() }
    }

    // MARK: - サイドバー

    /// 標準の `List(selection:)` はシステムのアクセント色（青）で選択を描き、
    /// テーマのアクセントに追従しない。項目数が固定なので自前の行で描く。
    /// 背景は本文と同じ（面を分けない）。選択行だけがアクセントで浮く。
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarHeader

                VStack(alignment: .leading, spacing: DSSpacing.m) {
                    ForEach(AgentConsoleAgent.allCases) { agent in
                        agentGroup(agent)
                    }
                }
                .padding(.horizontal, DSSpacing.s)
                .padding(.bottom, DSSpacing.l)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
    }

    private func agentGroup(_ agent: AgentConsoleAgent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            AgentConsoleGroupHeader(
                title: agent.displayName,
                systemImage: agent.symbolName,
                tint: agent.tint
            )
            .padding(.horizontal, DSSpacing.s)
            .padding(.bottom, DSSpacing.xxs)

            ForEach(AgentConsoleSection.sections(for: agent)) { section in
                AgentConsoleSectionRow(
                    section: section,
                    isSelected: (selection ?? .claudeStatus) == section
                ) {
                    selection = section
                }
            }
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: DSSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .fill(DSColor.newSessionGradient)
                    .frame(width: 30, height: 30)
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("エージェント")
                    .font(DSFont.captionStrong)
                    .foregroundStyle(DSColor.textPrimary)
                Text("管理コンソール")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.top, DSSpacing.m)
        .padding(.bottom, DSSpacing.l)
    }

    private func reload() async {
        // composition より先にウィンドウが復元された場合の保険。GUI プロセスの PATH は
        // 最小限なので、login shell から取り直してから各 CLI を探す。
        let givenPath = pathEnvironment
        let needsPathLookup = claudeExecutablePath == nil || givenPath.isEmpty
        let resolved = await Task.detached(priority: .userInitiated) {
            () -> (path: String, claude: String?, codex: String?, cursor: String?) in
            let env = needsPathLookup ? BinaryPathResolver.resolvePathEnvironment() : givenPath
            return (
                env,
                BinaryPathResolver.resolveBinary("claude", pathEnv: env),
                BinaryPathResolver.resolveBinary("codex", pathEnv: env),
                BinaryPathResolver.resolveBinary("cursor-agent", pathEnv: env)
            )
        }.value
        let path = resolved.path
        let claudePath = claudeExecutablePath ?? resolved.claude

        claude.updateEnvironment(
            claudeExecutablePath: claudePath,
            pathEnvironment: path,
            projectDirectory: projectDirectory
        )
        codex.updateEnvironment(
            executablePath: resolved.codex,
            pathEnvironment: path,
            projectDirectory: projectDirectory
        )
        cursor.updateEnvironment(executablePath: resolved.cursor, pathEnvironment: path)

        claude.loadSettings()
        codex.loadConfig()
        cursor.loadSettings()

        await claude.loadVersion()
        await claude.loadPlugins()
        await codex.loadVersion()
        await cursor.loadVersionAndModels()
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .claudeStatus {
        case .claudeStatus: ClaudeStatusPane(model: claude)
        case .claudePlugins: ClaudePluginsPane(model: claude)
        case .claudePermissions: ClaudePermissionsPane(model: claude)
        case .claudeMemory: ClaudeMemoryPane(model: claude)
        case .claudeHooks: ClaudeHooksPane(model: claude)
        case .claudeStatusLine: ClaudeStatusLinePane(model: claude)
        case .claudeOutputStyle: ClaudeOutputStylePane(model: claude)
        case .codexStatus: CodexStatusPane(model: codex)
        case .codexSettings: CodexSettingsPane(model: codex)
        case .codexPlugins: CodexPluginsPane(model: codex)
        case .codexMCP: CodexMCPPane(model: codex)
        case .codexMemory: CodexMemoryPane(model: codex)
        case .codexTrust: CodexTrustPane(model: codex)
        case .cursorStatus: CursorStatusPane(model: cursor)
        case .cursorPermissions: CursorPermissionsPane(model: cursor)
        case .cursorModel: CursorModelPane(model: cursor)
        case .cursorMCP: CursorMCPPane(model: cursor)
        case .cursorSettings: CursorSettingsPane(model: cursor)
        }
    }

    /// 結果と失敗は、いま見ているエージェントのものだけを出す。
    @ViewBuilder
    private var messageBar: some View {
        switch (selection ?? .claudeStatus).agent {
        case .claude:
            banner(error: claude.errorMessage, info: claude.infoMessage) { claude.clearMessages() }
        case .codex:
            banner(error: codex.errorMessage, info: codex.infoMessage) { codex.clearMessages() }
        case .cursor:
            banner(error: cursor.errorMessage, info: cursor.infoMessage) { cursor.clearMessages() }
        }
    }

    @ViewBuilder
    private func banner(error: String?, info: String?, dismiss: @escaping () -> Void) -> some View {
        if let error {
            AgentConsoleBanner(text: error, isError: true, onDismiss: dismiss)
        } else if let info {
            AgentConsoleBanner(text: info, isError: false, onDismiss: dismiss)
        }
    }
}

/// サイドバー1行。選択はテーマのアクセント色で描き、ホバーは薄い面で示す。
private struct AgentConsoleSectionRow: View {
    let section: AgentConsoleSection
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DSSpacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                        .fill(isSelected ? tint.opacity(0.22) : DSColor.fillSubtle)
                        .frame(width: 24, height: 24)
                    Image(systemName: section.symbolName)
                        .font(.system(size: DSIconSize.m, weight: .semibold))
                        .foregroundStyle(isSelected ? tint : DSColor.textSecondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.title)
                        .font(DSFont.body)
                        .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textSecondary)
                    Text(section.detail)
                        .font(DSFont.monoCaption)
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DSSpacing.s)
            .padding(.horizontal, DSSpacing.s)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .fill(background)
            }
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var tint: Color { section.agent.tint }

    private var background: Color {
        if isSelected { return tint.opacity(isHovering ? 0.16 : 0.12) }
        return isHovering ? DSColor.fillSubtle : .clear
    }
}

/// 結果と失敗を同じ場所に出すための帯。閉じるまで残す（トーストで流さない）。
struct AgentConsoleBanner: View {
    let text: String
    let isError: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: DSIconSize.l))
                .foregroundStyle(isError ? DSColor.statusError : DSColor.statusCompleted)
            Text(text)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: DSIconSize.s, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(HoverableIconButtonStyle())
        }
        .padding(.horizontal, DSSpacing.xl)
        .padding(.vertical, DSSpacing.m)
        .background((isError ? DSColor.statusError : DSColor.statusCompleted).opacity(0.10))
    }
}

/// 各ペインの共通の枠（見出し＋説明＋本文）。
///
/// 見出し行の右にはアイコン程度の軽い操作だけを置き、フィルタやセグメント等の
/// 幅を食う操作は `controls`（見出しの下の帯）へ逃がす。見出しと同居させると
/// 説明文が押しつぶされて読めなくなるため。
struct AgentConsolePane<Content: View>: View {
    let title: String
    let subtitle: String
    var toolbar: AnyView?
    var controls: AnyView?
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        subtitle: String,
        toolbar: AnyView? = nil,
        controls: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.toolbar = toolbar
        self.controls = controls
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DSSpacing.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DSFont.heroTitle)
                        .foregroundStyle(DSColor.textPrimary)
                    // fixedSize(vertical:) を付けると、幅が確定する前の測定で
                    // 1文字ずつ折り返した巨大な理想高さが出て、レイアウト全体が
                    // 上へずれる（見出しがタイトルバーに潜る）。行数で抑える。
                    Text(subtitle)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: DSSpacing.m)
                toolbar
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.top, DSSpacing.xl)
            .padding(.bottom, controls == nil ? DSSpacing.l : DSSpacing.m)

            if let controls {
                controls
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.bottom, DSSpacing.m)
            }

            // 見出しと本文の間に区切り線は引かない（面を割らない）。間隔だけで分ける。
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
