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
