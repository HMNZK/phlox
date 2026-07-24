import CryptoKit
import Foundation
import Testing
import AgentDomain
@testable import AppBootstrap

@Suite struct APNsEnvironmentFileTests {
    @Test func parsesSupportedShellSyntaxAndExpandsHomeDirectory() {
        let homeDirectory = "/Users/tester"
        let contents = """
            # comment

            export PHLOX_APNS_KEY_ID="KEY=123"
            PHLOX_APNS_TEAM_ID='TEAM123'
            PHLOX_APNS_AUTH_KEY_PATH="$HOME/.phlox/AuthKey.p8"
            PHLOX_APNS_AUTH_KEY_PEM='~/keys/AuthKey.pem'
            IGNORED_KEY=ignored
            """

        let values = APNsNotificationBridge.parseAPNsEnvironmentFile(
            contents,
            homeDirectory: homeDirectory
        )

        #expect(values[APNsNotificationBridge.keyIDEnvironmentKey] == "KEY=123")
        #expect(values[APNsNotificationBridge.teamIDEnvironmentKey] == "TEAM123")
        #expect(
            values[APNsNotificationBridge.authKeyPathEnvironmentKey]
                == "/Users/tester/.phlox/AuthKey.p8"
        )
        #expect(
            values[APNsNotificationBridge.authKeyPEMEnvironmentKey]
                == "/Users/tester/keys/AuthKey.pem"
        )
        #expect(values["IGNORED_KEY"] == nil)
    }

    @Test func processEnvironmentTakesPrecedenceOverFileValues() {
        let resolved = APNsNotificationBridge.resolveCredentialEnvironment(
            environment: [
                APNsNotificationBridge.keyIDEnvironmentKey: "ENV_KEY",
                APNsNotificationBridge.authKeyPEMEnvironmentKey: "ENV_PEM",
            ],
            homeDirectory: "/Users/tester",
            credentialsFileLoader: { path in
                #expect(path == "/Users/tester/.phlox/apns.env")
                return """
                    PHLOX_APNS_KEY_ID=FILE_KEY
                    PHLOX_APNS_TEAM_ID=FILE_TEAM
                    PHLOX_APNS_AUTH_KEY_PEM=FILE_PEM
                    PHLOX_APNS_AUTH_KEY_PATH=~/file-key.p8
                    """
            }
        )

        #expect(resolved.values[APNsNotificationBridge.keyIDEnvironmentKey] == "ENV_KEY")
        #expect(resolved.values[APNsNotificationBridge.teamIDEnvironmentKey] == "FILE_TEAM")
        #expect(resolved.values[APNsNotificationBridge.authKeyPEMEnvironmentKey] == "ENV_PEM")
        #expect(
            resolved.values[APNsNotificationBridge.authKeyPathEnvironmentKey]
                == "/Users/tester/file-key.p8"
        )
        #expect(!resolved.fileBackedKeys.contains(APNsNotificationBridge.keyIDEnvironmentKey))
        #expect(resolved.fileBackedKeys.contains(APNsNotificationBridge.teamIDEnvironmentKey))
        #expect(!resolved.fileBackedKeys.contains(APNsNotificationBridge.authKeyPEMEnvironmentKey))
    }

    @Test func emptyOrWhitespaceEnvironmentValuesFallBackToFileValues() {
        let resolved = APNsNotificationBridge.resolveCredentialEnvironment(
            environment: [
                APNsNotificationBridge.keyIDEnvironmentKey: "",
                APNsNotificationBridge.teamIDEnvironmentKey: " \t ",
            ],
            homeDirectory: "/Users/tester",
            credentialsFileLoader: { _ in
                """
                PHLOX_APNS_KEY_ID=FILE_KEY
                PHLOX_APNS_TEAM_ID=FILE_TEAM
                """
            }
        )

        #expect(resolved.values[APNsNotificationBridge.keyIDEnvironmentKey] == "FILE_KEY")
        #expect(resolved.values[APNsNotificationBridge.teamIDEnvironmentKey] == "FILE_TEAM")
        #expect(resolved.fileBackedKeys.contains(APNsNotificationBridge.keyIDEnvironmentKey))
        #expect(resolved.fileBackedKeys.contains(APNsNotificationBridge.teamIDEnvironmentKey))
    }

    @Test func parsesMultilineDoubleQuotedPEMValue() {
        let contents = #"""
            PHLOX_APNS_AUTH_KEY_PEM="-----BEGIN PRIVATE KEY-----
            PRIVATE-KEY-LINE-1
            PRIVATE-KEY-LINE-2
            -----END PRIVATE KEY-----"
            """#

        let values = APNsNotificationBridge.parseAPNsEnvironmentFile(
            contents,
            homeDirectory: "/Users/tester"
        )

        #expect(
            values[APNsNotificationBridge.authKeyPEMEnvironmentKey]
                == """
                -----BEGIN PRIVATE KEY-----
                PRIVATE-KEY-LINE-1
                PRIVATE-KEY-LINE-2
                -----END PRIVATE KEY-----
                """
        )
    }

    @Test func expandsBracedHomeDirectoryVariable() {
        let values = APNsNotificationBridge.parseAPNsEnvironmentFile(
            "PHLOX_APNS_AUTH_KEY_PATH=${HOME}/.phlox/AuthKey.p8",
            homeDirectory: "/Users/tester"
        )

        #expect(
            values[APNsNotificationBridge.authKeyPathEnvironmentKey]
                == "/Users/tester/.phlox/AuthKey.p8"
        )
    }

    @Test func missingCredentialsFileLeavesEnvironmentUnchanged() {
        let environment = [
            APNsNotificationBridge.keyIDEnvironmentKey: "ENV_KEY",
        ]

        let resolved = APNsNotificationBridge.resolveCredentialEnvironment(
            environment: environment,
            homeDirectory: "/Users/tester",
            credentialsFileLoader: { _ in
                throw CocoaError(.fileNoSuchFile)
            }
        )

        #expect(resolved.values == environment)
        #expect(resolved.fileBackedKeys.isEmpty)
    }

    @Test func configuredFromEnvironmentFallsBackToCredentialsFile() async {
        let privateKey = P256.Signing.PrivateKey()
        let store = APNsEnvironmentCountingDeviceTokenStore()
        let bridge = APNsNotificationBridge.configuredFromEnvironment(
            deviceTokenStore: store,
            environment: [:],
            homeDirectory: "/Users/tester",
            credentialsFileLoader: { _ in
                """
                PHLOX_APNS_KEY_ID=FILE_KEY
                PHLOX_APNS_TEAM_ID=FILE_TEAM
                PHLOX_APNS_AUTH_KEY_PATH=~/.phlox/AuthKey.p8
                """
            },
            fileLoader: { path in
                #expect(path == "/Users/tester/.phlox/AuthKey.p8")
                return privateKey.pemRepresentation
            }
        )

        await bridge.notify(.sessionCompleted(sessionId: "session-123", sessionName: "Bright Lily"))

        #expect(store.loadAllCallCount == 1)
    }
}

private final class APNsEnvironmentCountingDeviceTokenStore: DeviceTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var loadAllCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func loadAll() throws -> [DeviceTokenRegistration] {
        lock.lock()
        count += 1
        lock.unlock()
        return []
    }

    func upsert(_ registration: DeviceTokenRegistration) throws {}

    func remove(deviceToken: String) throws {}
}
