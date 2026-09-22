import Foundation
import Testing
@testable import PhloxCore

// task-1 受け入れテスト（PM 著・凍結。実装役は編集禁止 — ハーネス欠陥は PM 承認の上ハーネス部分のみ修理可）。
// 契約の正本: doc/apns-implementation-request.md（v1）
struct APNsModelsAcceptanceTests {

    // MARK: - Data.hexEncodedString

    @Test func デバイストークンのhex化は小文字連結() {
        let token = Data([0x0A, 0xFF, 0x00, 0x1B, 0xC4])
        #expect(token.hexEncodedString == "0aff001bc4")
    }

    @Test func 空Dataのhexは空文字列() {
        #expect(Data().hexEncodedString == "")
    }

    // MARK: - APNsEnvironment

    @Test func rawValueは契約の文字列() {
        #expect(APNsEnvironment.sandbox.rawValue == "sandbox")
        #expect(APNsEnvironment.production.rawValue == "production")
    }

    // 旧契約「Debug=開発署名=sandbox」は 2026-09-22 の調査（実ログ・Keychain 実データ）で誤りと確定したため、
    // 実際の aps-environment entitlement を実行時に読む契約へ改訂（PM 裁定）。
    @Test func development文字列はsandboxと判定する() {
        #expect(APNsEnvironment.resolve(apsEnvironmentValue: "development") == .sandbox)
    }

    @Test func production文字列はproductionと判定する() {
        #expect(APNsEnvironment.resolve(apsEnvironmentValue: "production") == .production)
    }

    @Test func 不正なプロファイルバイト列はnilを返す() {
        let corrupted = Data("<?xml not valid plist content </plist>".utf8)
        #expect(APNsEnvironment.resolve(embeddedProvisioningProfileData: corrupted) == nil)
    }

    @Test func macOSホストのswiftTestではプロファイル無しでproductionにフォールバックする() {
        // swift test は macOS ホストで走り、embedded.mobileprovision も Simulator でもないため production。
        #expect(APNsEnvironment.current == .production)
    }

    // MARK: - DeviceTokenRegistration（POST /device-tokens の body 契約）

    @Test func 登録リクエストのJSONは契約の3キーのみ() throws {
        let registration = DeviceTokenRegistration(
            deviceToken: "0aff001bc4",
            bundleId: "com.phlox.mobile.PhloxMobile",
            environment: .sandbox
        )
        let data = try JSONEncoder().encode(registration)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["deviceToken"] as? String == "0aff001bc4")
        #expect(object["bundleId"] as? String == "com.phlox.mobile.PhloxMobile")
        #expect(object["environment"] as? String == "sandbox")
        #expect(object.count == 3, "契約 v1 のキーは deviceToken/bundleId/environment のみ")
    }

    // MARK: - PhloxPushPayload（受信ペイロード契約）

    private func contractUserInfo(type: String, sessionId: String? = "sess-1") -> [AnyHashable: Any] {
        var phlox: [String: Any] = ["v": 1, "type": type, "sessionName": "Rose"]
        if let sessionId { phlox["sessionId"] = sessionId }
        return [
            "aps": ["alert": ["title": "Rose", "body": "完了"], "sound": "default", "thread-id": sessionId ?? ""],
            "phlox": phlox,
        ]
    }

    @Test func session_completedを解釈する() throws {
        let payload = try #require(PhloxPushPayload(userInfo: contractUserInfo(type: "session_completed")))
        #expect(payload.type == .sessionCompleted)
        #expect(payload.sessionID == "sess-1")
        #expect(payload.sessionName == "Rose")
        #expect(payload.version == 1)
    }

    @Test func approval_pendingを解釈する() throws {
        let payload = try #require(PhloxPushPayload(userInfo: contractUserInfo(type: "approval_pending")))
        #expect(payload.type == .approvalPending)
    }

    @Test func 未知typeはunknownとして受理する() throws {
        // 前方互換: 未知の type 値で失敗・クラッシュしない（契約「未知の type 値は無視する」）
        let payload = try #require(PhloxPushPayload(userInfo: contractUserInfo(type: "future_event")))
        #expect(payload.type == .unknown("future_event"))
        #expect(payload.sessionID == "sess-1")
    }

    @Test func 未知キーは無視して解釈する() throws {
        var userInfo = contractUserInfo(type: "session_completed")
        var phlox = try #require(userInfo["phlox"] as? [String: Any])
        phlox["futureKey"] = ["nested": true]
        userInfo["phlox"] = phlox
        userInfo["anotherRootKey"] = 42
        let payload = try #require(PhloxPushPayload(userInfo: userInfo))
        #expect(payload.type == .sessionCompleted)
    }

    @Test func phlox辞書が無ければnil() {
        let userInfo: [AnyHashable: Any] = ["aps": ["alert": ["title": "t"]]]
        #expect(PhloxPushPayload(userInfo: userInfo) == nil)
    }

    @Test func sessionId欠落はnil() {
        #expect(PhloxPushPayload(userInfo: contractUserInfo(type: "session_completed", sessionId: nil)) == nil)
    }

    @Test func sessionName欠落でも解釈する() throws {
        let userInfo: [AnyHashable: Any] = [
            "phlox": ["v": 1, "type": "session_completed", "sessionId": "s2"],
        ]
        let payload = try #require(PhloxPushPayload(userInfo: userInfo))
        #expect(payload.sessionID == "s2")
        #expect(payload.sessionName == nil)
    }
}
