import SwiftUI
import DesignSystem

/// 状態ペインの1グループ。枠で囲わず、見出しと余白だけでまとまりを示す。
struct AgentConsoleStatusSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            AgentConsoleGroupHeader(title: title, systemImage: systemImage)
            VStack(spacing: 2) {
                content()
            }
        }
    }
}

/// 状態ペインの1行。ラベルを左、値を右に置く。
struct AgentConsoleStatusRow: View {
    let label: String
    var value: String?
    var valueTint: Color = DSColor.textSecondary
    var mono: String?
    var note: String?

    var body: some View {
        HStack(spacing: DSSpacing.m) {
            Text(label)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textSecondary)
            Spacer(minLength: DSSpacing.m)
            if let note {
                Text(note)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            if let mono {
                Text(mono)
                    .font(DSFont.monoCaption)
                    .foregroundStyle(valueTint)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let value {
                Text(value)
                    .font(DSFont.caption)
                    .foregroundStyle(valueTint)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, DSSpacing.xs)
    }
}

/// 件数を一目で見せるタイル。枠線なしで、面をごく浅くくぼませるだけ。
struct AgentConsoleStatusTile: View {
    let title: String
    let value: String
    let detail: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: DSIconSize.m, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                if let detail {
                    Text(detail)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.m)
        .background {
            RoundedRectangle(cornerRadius: AgentConsoleStyle.cardRadius, style: .continuous)
                .fill(DSColor.fillSubtle)
        }
    }
}

/// 一覧を絞り込む検索欄。枠線は引かず、淡い面だけで入力欄と分かるようにする。
struct AgentConsoleSearchField: View {
    @Binding var text: String
    var placeholder: String = "絞り込み"
    var maxWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: DSIconSize.m))
                .foregroundStyle(DSColor.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DSFont.caption)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DSIconSize.m))
                        .foregroundStyle(DSColor.textTertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .fill(DSColor.fillSubtle)
        }
        .frame(maxWidth: maxWidth)
    }
}

/// バージョン・マーケットプレイス名などの補助情報チップ。
struct AgentConsoleMetaChip: View {
    let text: String
    var symbolName: String?
    var tint: Color = DSColor.textTertiary

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: DSIconSize.s, weight: .semibold))
            }
            Text(text)
                .font(DSFont.monoCaption)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, 1)
        .background(tint.opacity(0.14), in: Capsule(style: .continuous))
    }
}

/// CLI が見つからないときの案内。操作系を出しても失敗するだけなので理由を先に見せる。
struct AgentConsoleUnavailableNotice: View {
    let commandName: String

    var body: some View {
        VStack(spacing: DSSpacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DSColor.textTertiary)
            Text("\(commandName) コマンドが見つかりません")
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
            Text("インストールしたうえで Phlox を起動し直してください。")
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 「文字列1つを足す」だけの入力欄（ルール・サーバー名など）。
struct AgentConsoleAddField: View {
    let placeholder: String
    let buttonTitle: String
    @Binding var text: String
    var isMonospaced = true
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.s) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(isMonospaced ? DSFont.monoCaption : DSFont.caption)
                .onSubmit(onSubmit)
            Button(buttonTitle, action: onSubmit)
                .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
