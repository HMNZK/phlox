import AppBootstrap
import Foundation
import Sparkle

final class SessionRuntimeUpdateDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard SessionRuntimeUpdateCompatibility.allows(
            minimum: item.propertiesDictionary["phloxRuntimeProtocolMin"] as? String,
            maximum: item.propertiesDictionary["phloxRuntimeProtocolMax"] as? String,
            runtimeProtocol: SessionRuntimeDiscovery.currentProtocolVersion
        ) else {
            throw NSError(domain: "Phlox.SessionRuntimeUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "セッションの実行サービスと互換性を確認できないため、この更新を延期します。"])
        }
    }
}
