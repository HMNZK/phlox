import Foundation
import Testing
import PhloxCore

/// task-3 受け入れテスト（PM 著・実装役は編集禁止）。
/// レビュー #4（CWE-20）: リモート push の sessionId は信頼境界をまたぐ入力。
/// 内容検証（許可文字種・長さ）を通らないペイロードは init が nil で拒否する。
/// 許可: 英数字・ハイフン・アンダースコア、1〜128 文字。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
struct PushPayloadValidationAcceptanceTests {
    private func userInfo(sessionId: Any) -> [AnyHashable: Any] {
        ["phlox": ["v": 1, "type": "session_completed", "sessionId": sessionId] as [String: Any]]
    }

    @Test("正常な sessionId は受理する")
    func acceptsValidSessionID() throws {
        let uuid = "5E0C7C6A-2B1F-4A5B-9C3D-0F1E2D3C4B5A"
        let payload = try #require(PhloxPushPayload(userInfo: userInfo(sessionId: uuid)))
        #expect(payload.sessionID == uuid)

        let simple = try #require(PhloxPushPayload(userInfo: userInfo(sessionId: "sess_01-abc")))
        #expect(simple.sessionID == "sess_01-abc")
    }

    @Test("空文字列の sessionId は拒否する")
    func rejectsEmptySessionID() {
        #expect(PhloxPushPayload(userInfo: userInfo(sessionId: "")) == nil)
    }

    @Test("パス区切り・トラバーサルを含む sessionId は拒否する")
    func rejectsPathLikeSessionID() {
        #expect(PhloxPushPayload(userInfo: userInfo(sessionId: "../../etc/passwd")) == nil)
        #expect(PhloxPushPayload(userInfo: userInfo(sessionId: "abc/def")) == nil)
        #expect(PhloxPushPayload(userInfo: userInfo(sessionId: "abc%2Fdef")) == nil)
    }

    @Test("空白・制御文字・過長の sessionId は拒否する")
    func rejectsWhitespaceControlAndOversize() {
        #expect(PhloxPushPayload(userInfo: userInfo(sessionId: "abc def")) == nil)
        #expect(PhloxPushPayload(userInfo: userInfo(sessionId: "abc\ndef")) == nil)
        #expect(PhloxPushPayload(userInfo: userInfo(sessionId: String(repeating: "a", count: 129))) == nil)
    }

    @Test("上限ちょうど（128 文字）は受理する")
    func acceptsMaxLengthSessionID() throws {
        let id = String(repeating: "a", count: 128)
        let payload = try #require(PhloxPushPayload(userInfo: userInfo(sessionId: id)))
        #expect(payload.sessionID == id)
    }
}
