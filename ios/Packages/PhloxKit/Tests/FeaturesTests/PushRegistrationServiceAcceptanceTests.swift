import Foundation
import Testing
import PhloxCore
import Features

// task-2 受け入れテスト（PM 著・凍結。実装役は編集禁止 — ハーネス欠陥は PM 承認の上ハーネス部分のみ修理可）。
// リトライ状態機械の契約（起動のたび・トークン変更時に再送。失敗は静かに保留し次トリガーで再送）を固定する。
// ※ このファイルは task-2 ディスパッチ時に Packages/PhloxKit/Tests/FeaturesTests/ へ配置・コミットされる。

private actor RecordingRegistrar: DeviceTokenRegistering {
    struct StubError: Error {}
    private(set) var attempts: [DeviceTokenRegistration] = []
    private var shouldFail = false

    func setShouldFail(_ fail: Bool) { shouldFail = fail }

    func registerDeviceToken(_ registration: DeviceTokenRegistration) async throws {
        attempts.append(registration)
        if shouldFail { throw StubError() }
    }
}

struct PushRegistrationServiceAcceptanceTests {

    private func makeService(registrar: RecordingRegistrar) -> PushRegistrationService {
        PushRegistrationService(
            registrar: registrar,
            bundleId: "com.phlox.mobile.PhloxMobile",
            environment: .sandbox
        )
    }

    @Test func トークン受領で小文字hexと構成情報を送信する() async throws {
        let registrar = RecordingRegistrar()
        let service = makeService(registrar: registrar)
        await service.updateDeviceToken(Data([0x0A, 0xFF, 0x1B]))
        let attempts = await registrar.attempts
        #expect(attempts.count == 1)
        let sent = try #require(attempts.first)
        #expect(sent.deviceToken == "0aff1b")
        #expect(sent.bundleId == "com.phlox.mobile.PhloxMobile")
        #expect(sent.environment == "sandbox")
    }

    @Test func 送信失敗はthrowせず次のretryIfNeededで再送する() async {
        let registrar = RecordingRegistrar()
        await registrar.setShouldFail(true)
        let service = makeService(registrar: registrar)
        await service.updateDeviceToken(Data([0x01])) // 静かに失敗する
        #expect(await registrar.attempts.count == 1)
        await registrar.setShouldFail(false)
        await service.retryIfNeeded() // 保留分を再送する
        #expect(await registrar.attempts.count == 2)
        #expect(await registrar.attempts.last?.deviceToken == "01")
    }

    @Test func 送信成功後のretryIfNeededは何もしない() async {
        let registrar = RecordingRegistrar()
        let service = makeService(registrar: registrar)
        await service.updateDeviceToken(Data([0x01]))
        await service.retryIfNeeded()
        #expect(await registrar.attempts.count == 1, "成功済みトークンを retryIfNeeded で再送しない")
    }

    @Test func トークン変更時は成功後でも再送する() async {
        let registrar = RecordingRegistrar()
        let service = makeService(registrar: registrar)
        await service.updateDeviceToken(Data([0x01]))
        await service.updateDeviceToken(Data([0x02]))
        let attempts = await registrar.attempts
        #expect(attempts.count == 2)
        #expect(attempts.last?.deviceToken == "02")
    }

    @Test func 同一トークンでもupdateDeviceTokenは都度送信する() async {
        // 「アプリ起動のたび再送（冪等 upsert）」をシンプルに保つ: update は常に送信する
        let registrar = RecordingRegistrar()
        let service = makeService(registrar: registrar)
        await service.updateDeviceToken(Data([0x01]))
        await service.updateDeviceToken(Data([0x01]))
        #expect(await registrar.attempts.count == 2)
    }

    @Test func トークン未受領ならretryIfNeededは送信しない() async {
        let registrar = RecordingRegistrar()
        let service = makeService(registrar: registrar)
        await service.retryIfNeeded()
        #expect(await registrar.attempts.isEmpty)
    }
}
