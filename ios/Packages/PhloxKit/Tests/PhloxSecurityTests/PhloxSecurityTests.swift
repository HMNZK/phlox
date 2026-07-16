import XCTest
import Security
import LocalAuthentication
import PhloxCore
@testable import PhloxSecurity

// E3-3 検証。実 Keychain / 実生体認証には触れず、セキュリティ上の決定（Keychain クエリ属性・
// アクセシビリティ・生体ポリシー fallback）と、TokenStore / Authenticating の契約を検証する。
final class PhloxSecurityTests: XCTestCase {

    // MARK: - KeychainStore（純粋ロジック・実 Keychain 不使用）

    func testKeychainBaseQueryHasGenericPasswordClassAndIdentity() {
        let query = KeychainStore.baseQuery(service: "svc", account: "acct")
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "svc")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "acct")
    }

    func testKeychainBaseQueryExcludesValueAndReturnFlags() {
        // ベースクエリは検索/削除用。値や返却フラグを混ぜない。
        let query = KeychainStore.baseQuery(service: "svc", account: "acct")
        XCTAssertNil(query[kSecValueData as String])
        XCTAssertNil(query[kSecReturnData as String])
    }

    func testKeychainAccessibilityIsDeviceOnlyWhenUnlocked() {
        // iCloud 同期禁止 + 端末内 + ロック解除時のみ（漏洩リスク最小）。
        XCTAssertEqual(
            KeychainStore.accessibility as String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }

    // MARK: - BiometricGate（ポリシー fallback・純粋ロジック）

    func testBiometricPolicyUsesBiometricsWhenAvailable() {
        XCTAssertEqual(BiometricGate.policy(canEvaluateBiometrics: true), .deviceOwnerAuthenticationWithBiometrics)
    }

    func testBiometricPolicyFallsBackToPasscode() {
        XCTAssertEqual(BiometricGate.policy(canEvaluateBiometrics: false), .deviceOwnerAuthentication)
    }

    // MARK: - Authenticating 契約（StubAuthenticator）

    func testStubAuthenticatorAllowsAndDenies() async throws {
        let allow = try await StubAuthenticator(allows: true).authenticate(reason: "r")
        XCTAssertTrue(allow)
        let deny = try await StubAuthenticator(allows: false).authenticate(reason: "r")
        XCTAssertFalse(deny)
    }

    // MARK: - TokenStore 契約（InMemoryTokenStore、実 Keychain 不使用）

    func testInMemoryTokenStoreRoundTripAndDelete() async throws {
        let store: TokenStore = InMemoryTokenStore()
        let initial = try await store.load()
        XCTAssertNil(initial)

        try await store.save("bearer-xyz")
        let loaded = try await store.load()
        XCTAssertEqual(loaded, "bearer-xyz")

        try await store.delete()
        let afterDelete = try await store.load()
        XCTAssertNil(afterDelete)
    }
}
