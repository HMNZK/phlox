import Testing
import Foundation
@testable import AgentDomain

@Test func appFlavor_release_appSupportDirectoryName_isPhlox() {
    #expect(AppFlavor.release.appSupportDirectoryName == "Phlox")
}

@Test func appFlavor_debug_appSupportDirectoryName_isPhloxDebug() {
    #expect(AppFlavor.debug.appSupportDirectoryName == "Phlox-Debug")
}

@Test func appFlavor_release_mobileTokenKeychainService_matchesLegacyLiteral() {
    #expect(AppFlavor.release.mobileTokenKeychainService == "com.phlox.Phlox.mobileToken")
}

@Test func appFlavor_debug_mobileTokenKeychainService_isDebugVariant() {
    #expect(AppFlavor.debug.mobileTokenKeychainService == "com.phlox.Phlox.debug.mobileToken")
}

@Test func appFlavor_runsLegacyMigration_releaseTrue_debugFalse() {
    #expect(AppFlavor.release.runsLegacyMigration == true)
    #expect(AppFlavor.debug.runsLegacyMigration == false)
}

@Test func appSupportLocator_homeBasedURL_usesFlavorDirectoryName() {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    let releaseURL = AppSupportLocator.appSupportDirectoryURL(flavor: .release, home: home)
    let debugURL = AppSupportLocator.appSupportDirectoryURL(flavor: .debug, home: home)

    #expect(releaseURL.lastPathComponent == "Phlox")
    #expect(debugURL.lastPathComponent == "Phlox-Debug")
}

// FileManager 経路（CompositionRoot が実際に使う版）も flavor 名で末尾が分岐することを固定する。
@Test func appSupportLocator_fileManagerBasedURL_appendsFlavorName() throws {
    let releaseURL = try AppSupportLocator.appSupportDirectoryURL(flavor: .release)
    let debugURL = try AppSupportLocator.appSupportDirectoryURL(flavor: .debug)

    #expect(releaseURL.lastPathComponent == "Phlox")
    #expect(debugURL.lastPathComponent == "Phlox-Debug")
}
