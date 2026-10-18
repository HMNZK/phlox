import SwiftUI
import DesignSystemIOS

struct SessionDetailCommandOutputView: View {
    let output: String
    let copyText: String?
    @State private var showsAll = false

    var body: some View {
        let display = SessionDetailTranscriptPresentation.commandOutput(output, expanded: showsAll)
        VStack(alignment: .leading, spacing: 0) {
            if !output.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(display.displayed)
                        .font(DSFont.campMonoCaption)
                        .foregroundStyle(IOSColor.text.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, DSSpacing.m)
                        .padding(.vertical, DSSpacing.s)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: DSSpacing.s) {
                if display.isTruncated {
                    Button("さらに表示（残り \(display.hiddenLineCount) 行）") {
                        showsAll = true
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("SessionDetailCommandOutput.showMore")
                }
                Spacer(minLength: 0)
                if let copyText {
                    Button("セクションをコピー") {
                        ChatMessageCopyAction.copyToPasteboard(copyText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("SessionDetailCommandOutput.copySection")
                }
            }
            .font(DSFont.caption)
            .foregroundStyle(IOSColor.text.secondary)
            .padding(.horizontal, DSSpacing.m)
            .padding(.top, DSSpacing.xs)
            .padding(.bottom, DSSpacing.s)
        }
    }
}
