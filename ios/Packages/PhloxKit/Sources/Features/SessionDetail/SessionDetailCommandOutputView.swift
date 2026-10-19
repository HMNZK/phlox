import SwiftUI
import DesignSystemIOS

struct SessionDetailCommandOutputView: View {
    let output: String
    let copyText: String?
    @State private var showsAll = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var lineSpacing = DSSpacing.xs

    var body: some View {
        let display = SessionDetailTranscriptPresentation.commandOutput(output, expanded: showsAll)
        let actionLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.s))
            : AnyLayout(HStackLayout(spacing: DSSpacing.s))
        VStack(alignment: .leading, spacing: 0) {
            if !output.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(Self.attributed(display.displayed))
                        .font(DSFont.campMonoCaption)
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(IOSColor.text.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, DSSpacing.m)
                        .padding(.vertical, DSSpacing.s)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(IOSColor.bg.code)
            }
            actionLayout {
                if display.isTruncated {
                    Button {
                        showsAll = true
                    } label: {
                        Text("さらに表示（残り \(display.hiddenLineCount) 行）")
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressFeedbackStyle())
                    .accessibilityIdentifier("SessionDetailCommandOutput.showMore")
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if let copyText {
                    Button {
                        ChatMessageCopyAction.copyToPasteboard(copyText)
                    } label: {
                        Text("セクションをコピー")
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressFeedbackStyle())
                    .accessibilityIdentifier("SessionDetailCommandOutput.copySection")
                }
            }
            .font(DSFont.iosCaption2)
            .foregroundStyle(IOSColor.text.secondary)
            .padding(.horizontal, DSSpacing.m)
            .padding(.top, DSSpacing.xs)
            .padding(.bottom, DSSpacing.s)
        }
    }

    /// Mac の TranscriptCardOutputLines と同じ分類。コピー元の文字列は加工しない。
    static func attributed(_ output: String) -> AttributedString {
        var result = AttributedString()
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var part = AttributedString(String(line))
            let passed = line.range(of: #"(?<!\d)0 failures"#, options: .regularExpression) != nil
            if line.contains("error") {
                part.foregroundColor = IOSColor.status.error
                part.inlinePresentationIntent = .stronglyEmphasized
            } else if line.hasPrefix("✔") || passed {
                part.foregroundColor = DSColor.diffAdded
                if passed { part.inlinePresentationIntent = .stronglyEmphasized }
            } else if line.range(of: #"^\[\d|^Building|started'?$"#, options: .regularExpression) != nil {
                part.foregroundColor = IOSColor.text.secondary
            }
            result += part
            if index < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }
}
