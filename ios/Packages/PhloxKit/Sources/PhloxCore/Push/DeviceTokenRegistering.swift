import Foundation

/// デバイストークン登録の DI シーム。PhloxAPI に足すと既存モック全部が壊れるため独立プロトコルにする。
public protocol DeviceTokenRegistering: Sendable {
    /// POST /device-tokens。成否は HTTP ステータスのみで判定（2xx=成功、それ以外は throw）。
    func registerDeviceToken(_ registration: DeviceTokenRegistration) async throws
}
