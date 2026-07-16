import Foundation
import Testing
@testable import SessionFeature

// task-2 白箱: 受け入れテストが触れない ReasoningPreview.tail 連携の補助検証。

private let t0 = Date(timeIntervalSince1970: 1_720_000_000)

@Test
func reasoningPreviewUsesTailOfLatestReasoningWhileRunning() {
    let transcript: [ChatItem] = [
        .reasoning(id: "r1", text: "l1\nl2\nl3\nl4", timestamp: t0),
    ]
    #expect(
        SubAgentDrawerPresentation.reasoningPreview(transcript: transcript, status: .running)
            == "l2\nl3\nl4"
    )
}

@Test
func reasoningPreviewOmitsBlankOnlyReasoningWhileRunning() {
    let transcript: [ChatItem] = [
        .reasoning(id: "r1", text: "  \n \n", timestamp: t0),
    ]
    #expect(SubAgentDrawerPresentation.reasoningPreview(transcript: transcript, status: .running) == nil)
}
