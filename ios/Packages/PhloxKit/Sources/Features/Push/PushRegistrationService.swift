import Foundation
import PhloxCore

/// デバイストークン登録のオーケストレーター。
/// - 送信失敗は握りつぶさず「未完了」として記録し、次のトリガー（retryIfNeeded）で再送する。
/// - Mac 側エンドポイント未マージの間は 404 が返るが、挙動は同じ（静かに失敗→次回再試行）。
public actor PushRegistrationService {
    private let registrar: any DeviceTokenRegistering
    private let bundleId: String
    private let environment: APNsEnvironment

    private var currentToken: Data?
    private var isSynced = false

    public init(registrar: any DeviceTokenRegistering, bundleId: String, environment: APNsEnvironment) {
        self.registrar = registrar
        self.bundleId = bundleId
        self.environment = environment
    }

    /// APNs からトークンを受領/変更したとき呼ぶ。hex 小文字化して即時送信する。
    /// 送信失敗でも throw しない（内部で保持し、次の retryIfNeeded で再送）。
    public func updateDeviceToken(_ deviceToken: Data) async {
        currentToken = deviceToken
        await sendCurrentToken()
    }

    /// 起動時・フォアグラウンド復帰時に呼ぶ。未送信/送信失敗のトークンがあれば再送する。
    /// 送信済み（成功）なら何もしない。トークン未受領なら何もしない。
    public func retryIfNeeded() async {
        guard currentToken != nil, !isSynced else { return }
        await sendCurrentToken()
    }

    private func sendCurrentToken() async {
        guard let deviceToken = currentToken else { return }

        let registration = DeviceTokenRegistration(
            deviceToken: deviceToken.hexEncodedString,
            bundleId: bundleId,
            environment: environment
        )

        do {
            try await registrar.registerDeviceToken(registration)
            if currentToken == deviceToken { isSynced = true }
        } catch {
            if currentToken == deviceToken { isSynced = false }
        }
    }
}
