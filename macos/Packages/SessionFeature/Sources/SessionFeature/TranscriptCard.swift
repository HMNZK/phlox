import AppKit
import SwiftUI
import DesignSystem

/// 見出し行の右端に出す短いしるし（「実行中」「+42」「−6」）。
struct TranscriptCardBadge: Identifiable {
    let id: String
    let text: Text
    var color: Color = DSColor.textTertiary
    var weight: Font.Weight = .semibold
    var monospaced = false
}

/// 会話の中の枠付きカード（PhloxChat.dc.html の isCard）。
/// 角丸 8・カード地・1pt の内枠（実行中は弱い文字色で濃く）。見出し行は 32pt で「› ラベル 等幅の要約 … しるし」。
/// 開くと区切り線の下に中身を出す。
struct TranscriptCard<Content: View>: View {
    @Binding var isExpanded: Bool
    let label: Text
    let summary: String?
    var isRunning = false
    var badges: [TranscriptCardBadge] = []
    @ViewBuilder let content: () -> Content
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(verbatim: "›")
                        .font(.system(size: 13 * scale))
                        .foregroundStyle(DSColor.textTertiary)
                        .frame(width: 10)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    label
                        .font(.system(size: 12 * scale, weight: .medium))
                        .foregroundStyle(DSColor.chatTextPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    Text(verbatim: summary ?? "")
                        .font(.system(size: 11.5 * scale, design: .monospaced))
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(badges) { badge in
                        badge.text
                            .font(.system(size: 11 * scale, weight: badge.weight, design: badge.monospaced ? .monospaced : .default))
                            .monospacedDigit()
                            .foregroundStyle(badge.color)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 32 * scale)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summary.map { Text("\(label)、\($0)") } ?? label)
            .accessibilityValue(isExpanded ? Text("展開中") : Text("折りたたみ中"))
            if isExpanded {
                Rectangle()
                    .fill(DSColor.separator)
                    .frame(height: 1)
                content()
            }
        }
        .background(DSColor.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isRunning ? DSColor.textTertiary : DSColor.separator, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// カード下端の「さらに表示（残り n 行）」と右端のコピー（PhloxChat.dc.html の more / copyLabel）。
struct TranscriptCardFooter: View {
    let hiddenLineCount: Int
    let onShowMore: () -> Void
    var copyText: String?
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        VStack(spacing: 0) {
            Rectangle()
                .fill(DSColor.separator)
                .frame(height: 1)
            HStack(spacing: 10) {
                if hiddenLineCount > 0 {
                    Button("さらに表示（残り \(hiddenLineCount) 行）", action: onShowMore)
                        .buttonStyle(.plain)
                        .foregroundStyle(DSColor.accentInk)
                        .accessibilityIdentifier("TranscriptCard.showMore")
                }
                Spacer(minLength: 0)
                if let copyText {
                    Button("セクションをコピー") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityIdentifier("TranscriptCard.copySection")
                }
            }
            .font(.system(size: 11.5 * scale))
            .padding(.leading, 28)
            .padding(.trailing, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
    }
}

/// コマンドの出力の行（等幅 11.5・行の高さ 1.7・左 28）。「error」を含む行は赤い文字（PhloxChat.dc.html の cmd）。
struct TranscriptCardOutputLines: View {
    let output: String
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        Text(Self.attributed(output))
            .font(.system(size: 11.5 * scale, design: .monospaced))
            .lineSpacing(5 * scale)
            .foregroundStyle(DSColor.chatTextPrimary)
            .chatTextSelection()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 28)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
    }

    static func attributed(_ output: String) -> AttributedString {
        var result = AttributedString()
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var part = AttributedString(String(line))
            if line.contains("error") {
                part.foregroundColor = DSColor.attentionInk(.error)
            }
            result += part
            if index < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }
}

/// 出力に書かれた終了コード（Claude Code の Bash は失敗時に先頭へ「Exit code N」を付ける）。
/// ponytail: 構造化された終了コードはどのエージェントの経路にも無いので、出力の文字列から拾える分だけ。
/// Codex / Cursor の終了コードを出すには StructuredChatKit の commandExecution へ値を通す必要がある。
enum CommandExitCode {
    static func parse(_ output: String) -> Int? {
        for line in output.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: true).prefix(3) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Exit code ") else { continue }
            return Int(trimmed.dropFirst("Exit code ".count).prefix { $0.isNumber })
        }
        return nil
    }

    /// 「exit N」のしるし。0 は弱い文字、0 以外はエラーの文字色で太く。
    static func badge(for output: String) -> TranscriptCardBadge? {
        guard let code = parse(output) else { return nil }
        return TranscriptCardBadge(
            id: "exit",
            text: Text(verbatim: "exit \(code)"),
            color: code == 0 ? DSColor.textTertiary : DSColor.attentionInk(.error),
            weight: code == 0 ? .regular : .semibold
        )
    }
}
