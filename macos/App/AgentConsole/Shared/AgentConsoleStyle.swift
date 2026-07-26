import SwiftUI
import DesignSystem

/// 管理ウィンドウ共通の見た目部品。DesignSystem のトークンだけで組み、
/// 設定画面（SettingsView）と同じ手触り（面・ホバー・アクセント）に揃える。
enum AgentConsoleStyle {
    /// 内容が縦に伸びるペインの左右余白。
    static let contentInset = DSSpacing.l
    /// カード行の角丸。
    static let cardRadius = DSRadius.l
}

/// リストの1件を包む面。**枠線は引かない**——画面全体を1枚の板として見せるため、
/// 区切りは余白と（必要なときだけ）ごく淡い面で表す。
struct AgentConsoleCard<Content: View>: View {
    var isHighlighted = false
    @ViewBuilder var content: () -> Content

    @State private var isHovering = false

    var body: some View {
        content()
            .padding(.vertical, DSSpacing.m)
            .padding(.horizontal, DSSpacing.l)
            .background {
                RoundedRectangle(cornerRadius: AgentConsoleStyle.cardRadius, style: .continuous)
                    .fill(fill)
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
            }
    }

    private var fill: Color {
        if isHighlighted { return DSColor.accent.opacity(isHovering ? 0.13 : 0.09) }
        return isHovering ? DSColor.fillSubtle : .clear
    }
}

/// 見出し・タイル・入力欄など、ホバーしない静的なまとまりの面。枠線は引かない。
struct AgentConsoleGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: AgentConsoleStyle.cardRadius, style: .continuous)
                    .fill(DSColor.fillSubtle)
            }
    }
}

/// ペイン内のグループ見出し。Form のセクションヘッダより静かに、字間を広めに置く。
struct AgentConsoleGroupHeader: View {
    let title: String
    var systemImage: String?
    var tint: Color = DSColor.textTertiary
    var detail: String?

    var body: some View {
        HStack(spacing: DSSpacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: DSIconSize.m, weight: .semibold))
                    .foregroundStyle(tint)
            }
            // 大文字化はしない。フック名（PostToolUse 等）が読みづらくなるため。
            Text(title)
                .font(DSFont.captionStrong)
                .tracking(0.4)
                .foregroundStyle(tint)
            if let detail {
                Text(detail)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 空状態。中央に薄いアイコンと一言を置く（リストがゼロ件のとき）。
struct AgentConsoleEmptyState: View {
    let symbolName: String
    let message: String

    var body: some View {
        VStack(spacing: DSSpacing.s) {
            Image(systemName: symbolName)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DSColor.textTertiary.opacity(0.7))
            Text(message)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xxl)
    }
}

/// ペインのツールバーに置く丸いアイコンボタン。
struct AgentConsoleIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: DSIconSize.m, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(help)
    }
}

/// 「あと少しで押せる」ことを示す控えめな主ボタン（追加・保存など）。
struct AgentConsoleActionButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, isProminent: isProminent)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let isProminent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
            configuration.label
                .font(DSFont.caption.weight(.semibold))
                .foregroundStyle(isProminent ? Color.white : DSColor.textPrimary)
                .padding(.vertical, 5)
                .padding(.horizontal, DSSpacing.m)
                .background {
                    if isProminent {
                        shape.fill(DSColor.accent.opacity(configuration.isPressed ? 0.75 : (isHovering ? 1.0 : 0.9)))
                    } else {
                        // 枠線は引かない。押せることは面の濃さだけで示す。
                        shape.fill(configuration.isPressed ? DSColor.fillSelected : (isHovering ? DSColor.fillSubtle : DSColor.fillSubtle.opacity(0.6)))
                    }
                }
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(shape)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
                }
                .dsInteractiveCursor(isEnabled: isEnabled)
        }
    }
}

extension View {
    /// ペイン本文の共通レイアウト（左右余白つきの縦スクロール）。
    func agentConsoleScrollBody() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                self
            }
            .padding(.horizontal, AgentConsoleStyle.contentInset)
            .padding(.vertical, DSSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}
