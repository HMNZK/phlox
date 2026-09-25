import Testing
import PhloxCore

struct PhloxPushPayloadTests {
    @Test("英数字・ハイフン・アンダースコアを受理する")
    func acceptsAllowedSessionIDCharacters() {
        #expect(payload(sessionID: "aZ09-_")?.sessionID == "aZ09-_")
    }

    @Test("長さの下限と上限だけを受理する")
    func checksSessionIDLengthBoundaries() {
        #expect(payload(sessionID: "a") != nil)
        #expect(payload(sessionID: String(repeating: "a", count: 128)) != nil)
        #expect(payload(sessionID: "") == nil)
        #expect(payload(sessionID: String(repeating: "a", count: 129)) == nil)
    }

    @Test("許可文字以外を拒否する")
    func rejectsDisallowedSessionIDCharacters() {
        for sessionID in ["abc/def", "abc.def", "abc def", "abc%2Fdef", "abc\ndef", "セッション"] {
            #expect(payload(sessionID: sessionID) == nil)
        }
    }

    private func payload(sessionID: String) -> PhloxPushPayload? {
        PhloxPushPayload(userInfo: [
            "phlox": ["v": 1, "type": "session_completed", "sessionId": sessionID]
        ])
    }
}

// C-62・B5: パソコンから届く種類をすべて名前つきで読む（質問は承認と別）。
@Test("パソコンの通知の種類をすべて読む", arguments: [
    ("session_completed", PhloxPushPayload.EventType.sessionCompleted),
    ("approval_pending", .approvalPending),
    ("question_pending", .questionPending),
    ("session_error", .sessionError),
    ("session_stalled", .sessionStalled),
    ("session_exited", .sessionExited),
    ("future_kind", .unknown("future_kind")),
])
func decodesEveryDesktopNotificationKind(type: String, expected: PhloxPushPayload.EventType) throws {
    let payload = try #require(PhloxPushPayload(userInfo: ["phlox": ["v": 1, "type": type, "sessionId": "session-1"]]))
    #expect(payload.type == expected)
}
