import Foundation
import Testing
import PhloxCore

struct PushModelsTests {

    @Test func hexは各バイトを2桁小文字で連結する() {
        let token = Data([0x00, 0x0F, 0xA0, 0xFF])
        #expect(token.hexEncodedString == "000fa0ff")
    }

    @Test func production環境の登録JSON() throws {
        let registration = DeviceTokenRegistration(
            deviceToken: "abc",
            bundleId: "com.example.app",
            environment: .production
        )
        let data = try JSONEncoder().encode(registration)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["environment"] as? String == "production")
    }

    @Test func v欠落時はversion1とみなす() throws {
        let userInfo: [AnyHashable: Any] = [
            "phlox": ["type": "session_completed", "sessionId": "s1"],
        ]
        let payload = try #require(PhloxPushPayload(userInfo: userInfo))
        #expect(payload.version == 1)
    }

    @Test func sessionIdが文字列以外ならnil() {
        let userInfo: [AnyHashable: Any] = [
            "phlox": ["type": "session_completed", "sessionId": 42],
        ]
        #expect(PhloxPushPayload(userInfo: userInfo) == nil)
    }

    @Test func 空typeはunknown空文字列() throws {
        let userInfo: [AnyHashable: Any] = [
            "phlox": ["v": 1, "type": "", "sessionId": "s1"],
        ]
        let payload = try #require(PhloxPushPayload(userInfo: userInfo))
        #expect(payload.type == .unknown(""))
    }
}
