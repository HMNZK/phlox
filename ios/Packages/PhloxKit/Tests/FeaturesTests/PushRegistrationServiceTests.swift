import Foundation
import Testing
import PhloxCore
import Features

private actor GatedRegistrar: DeviceTokenRegistering {
    struct Failure: Error {}

    private(set) var attempts: [DeviceTokenRegistration] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var gateForFirst = false
    private var failNext = false

    func received() -> Int { attempts.count }

    func setFailNext(_ f: Bool) { failNext = f }

    func gateFirst() { gateForFirst = true }

    func releaseGate() {
        gate?.resume()
        gate = nil
    }

    func registerDeviceToken(_ registration: DeviceTokenRegistration) async throws {
        attempts.append(registration)
        if gateForFirst {
            gateForFirst = false
            await withCheckedContinuation { gate = $0 }
        }
        if failNext {
            failNext = false
            throw Failure()
        }
    }
}

private actor StubRegistrar: DeviceTokenRegistering {
    struct Failure: Error {}

    private(set) var attempts: [DeviceTokenRegistration] = []
    private var failCount = 0

    func setFailCount(_ count: Int) { failCount = count }

    func registerDeviceToken(_ registration: DeviceTokenRegistration) async throws {
        attempts.append(registration)
        if failCount > 0 {
            failCount -= 1
            throw Failure()
        }
    }
}

struct PushRegistrationServiceTests {

    private func makeService(
        registrar: any DeviceTokenRegistering,
        bundleId: String = "com.example.test",
        environment: APNsEnvironment = .production
    ) -> PushRegistrationService {
        PushRegistrationService(
            registrar: registrar,
            bundleId: bundleId,
            environment: environment
        )
    }

    @Test func retryIfNeededは失敗が解消するまで都度再送する() async {
        let registrar = StubRegistrar()
        await registrar.setFailCount(3)
        let service = makeService(registrar: registrar)
        await service.updateDeviceToken(Data([0x0A]))
        await service.retryIfNeeded()
        await service.retryIfNeeded()
        #expect(await registrar.attempts.count == 3)
        await service.retryIfNeeded()
        #expect(await registrar.attempts.count == 4)
        await service.retryIfNeeded()
        #expect(await registrar.attempts.count == 4, "成功後の retryIfNeeded は追加送信しない")
    }

    @Test func 失敗後に新トークンでupdateすると即時送信しretryは不要() async {
        let registrar = StubRegistrar()
        await registrar.setFailCount(1)
        let service = makeService(registrar: registrar)
        await service.updateDeviceToken(Data([0x01]))
        await service.updateDeviceToken(Data([0x02]))
        let attempts = await registrar.attempts
        #expect(attempts.count == 2)
        #expect(attempts.last?.deviceToken == "02")
        await service.retryIfNeeded()
        #expect(await registrar.attempts.count == 2, "新トークン送信成功後は retry 不要")
    }

    @Test func 古い成功が現在トークンの失敗を隠蔽して再送を止めない() async {
        let registrar = GatedRegistrar()
        let service = makeService(registrar: registrar)
        await registrar.gateFirst()
        async let a: Void = service.updateDeviceToken(Data([0x0A]))
        while await registrar.received() < 1 { await Task.yield() }
        await registrar.setFailNext(true)
        await service.updateDeviceToken(Data([0x0B]))
        await registrar.releaseGate()
        await a
        await service.retryIfNeeded()
        #expect(
            await registrar.received() == 3,
            "古い A 成功が isSynced を誤って立て、現在トークン B の失敗が再送されない"
        )
    }

    @Test func init時のbundleIdとenvironmentが登録に渡る() async throws {
        let registrar = StubRegistrar()
        let service = makeService(
            registrar: registrar,
            bundleId: "com.phlox.custom",
            environment: .sandbox
        )
        await service.updateDeviceToken(Data())
        let sent = try #require(await registrar.attempts.first)
        #expect(sent.bundleId == "com.phlox.custom")
        #expect(sent.environment == "sandbox")
        #expect(sent.deviceToken == "")
    }
}
