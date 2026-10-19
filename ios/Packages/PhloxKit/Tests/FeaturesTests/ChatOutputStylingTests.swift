import SwiftUI
import Testing
import DesignSystemIOS
@testable import Features

@Suite("コマンド出力のMac準拠の強調")
@MainActor
struct ChatOutputStylingTests {
    @Test("出力の空行・末尾改行とコピー対象の原文を保持する")
    func preservesText() {
        let output = "Building\n\n✔ done\n0 failures\nerror: failed\n"
        let attributed = SessionDetailCommandOutputView.attributed(output)
        #expect(String(attributed.characters) == output)
    }

    @Test("成功数の0だけを強調し、10や100 failuresを成功扱いしない")
    func zeroFailuresIsNotASuffixMatch() {
        for output in ["10 failures", "100 failures", "ordinary output"] {
            let run = SessionDetailCommandOutputView.attributed(output)
            #expect(run.foregroundColor == nil)
            #expect(run.inlinePresentationIntent == nil)
        }
        let passed = SessionDetailCommandOutputView.attributed("Executed 3 tests, 0 failures")
        #expect(passed.foregroundColor == DSColor.diffAdded)
        #expect(passed.inlinePresentationIntent == .stronglyEmphasized)
    }

    @Test("エラーの強調を成功語より優先し、進捗は弱める")
    func prioritizesErrorsAndSeparatesProgress() {
        let error = SessionDetailCommandOutputView.attributed("error: 0 failures reported incorrectly")
        #expect(error.foregroundColor == IOSColor.status.error)
        #expect(error.inlinePresentationIntent == .stronglyEmphasized)
        let check = SessionDetailCommandOutputView.attributed("✔ finished")
        #expect(check.foregroundColor == DSColor.diffAdded)
        #expect(check.inlinePresentationIntent == nil)
        for output in ["[1/2] Compile", "Building for debugging...", "Test Suite started'"] {
            #expect(SessionDetailCommandOutputView.attributed(output).foregroundColor == IOSColor.text.secondary)
        }
    }

    @Test("空出力の実コピーボタンも標準・拡大文字で44pt以上の操作領域を持つ")
    func commandCopyFooterKeepsMinimumTouchHeight() {
        for typeSize in [DynamicTypeSize.large, .accessibility1, .accessibility5] {
            let size = measuredSize(SessionDetailCommandOutputView(output: "", copyText: "原文")
                .environment(\.dynamicTypeSize, typeSize))
            #expect(size.height >= 44)
            #expect(size.width <= 320.1)
        }
    }

    @Test("承認の長い差分行は全文の自然幅を保ち、同じ文字サイズの短い行と同じ高さになる")
    func expandedApprovalDiffPreservesLongUnwrappedLine() {
        for typeSize in [DynamicTypeSize.large, .accessibility1, .accessibility5] {
            let short = ReplyApprovalDiffContent(diff: "@@ -1 +1 @@\n+let value = 1")
            let long = ReplyApprovalDiffContent(diff: "@@ -1 +1 @@\n+let value = \"\(String(repeating: "longIdentifier", count: 15))\"")
            let shortSize = measuredSize(short.rows.environment(\.dynamicTypeSize, typeSize))
            let longSize = measuredSize(long.rows.environment(\.dynamicTypeSize, typeSize))
            let scrollSize = measuredSize(long.environment(\.dynamicTypeSize, typeSize))
            #expect(longSize.width > 320)
            #expect(longSize.width > shortSize.width)
            #expect(abs(longSize.height - shortSize.height) < 1)
            #expect(scrollSize.width <= 320.1)
            #expect(abs(scrollSize.height - longSize.height) < 1)
        }
    }

    private func measuredSize<Content: View>(_ content: Content) -> CGSize {
        let recorder = ChatBubbleSizeRecorder()
        let renderer = ImageRenderer(content: ChatBubbleProposal(width: 320, recorder: recorder) { content })
        renderer.render { _, _ in }
        return recorder.size
    }
}

@Suite("ユーザー吹き出しの幅")
@MainActor
struct ChatBubbleWidthTests {
    @Test("長文は本文幅の78%へ折り返し、短文は内容幅を保つ")
    func constrainsLongTextWithoutStretchingShortText() {
        let long = String(repeating: "折り返す会話本文", count: 40)
        let narrow = size(of: long, width: 300)
        let wide = size(of: long, width: 396)
        let short = size(of: "はい", width: 396)
        #expect(abs(narrow.width - 300 * 0.78) < 1)
        #expect(abs(wide.width - 396 * 0.78) < 1)
        #expect(narrow.height > wide.height)
        #expect(short.width < wide.width)
    }

    @Test("添付4枚は狭い幅で折り返し、広い幅では1行に収まる")
    func wrapsAttachments() {
        func measure(width: CGFloat) -> CGSize {
            let recorder = ChatBubbleSizeRecorder()
            let renderer = ImageRenderer(content: ChatBubbleProposal(width: width, recorder: recorder) {
                SessionDetailAttachmentLayout {
                    ForEach(0..<4) { _ in Color.clear.frame(width: 56, height: 56) }
                }
            })
            renderer.render { _, _ in }
            return recorder.size
        }
        let narrow = measure(width: 200)
        let wide = measure(width: 300)
        #expect(narrow.width <= 200)
        #expect(narrow.height > wide.height)
        #expect(wide.height == 56)
    }

    private func size(of text: String, width: CGFloat) -> CGSize {
        // Layoutへ本文幅を提案し、外側の全幅frameを含めず内容の実寸を測る。
        let recorder = ChatBubbleSizeRecorder()
        let renderer = ImageRenderer(content: ChatBubbleProposal(width: width, recorder: recorder) {
            SessionDetailBubbleLayout {
                Text(text)
                    .font(DSFont.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.m + DSSpacing.xxs)
            }
        })
        renderer.render { _, _ in }
        return recorder.size
    }
}

private final class ChatBubbleSizeRecorder: @unchecked Sendable {
    var size = CGSize.zero
}

private struct ChatBubbleProposal: Layout {
    let width: CGFloat
    let recorder: ChatBubbleSizeRecorder

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        recorder.size = size
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}
