import Foundation

/// APNs 環境。Debug ビルド（開発署名）= sandbox、それ以外（TestFlight/App Store）= production。
public enum APNsEnvironment: String, Sendable {
    case sandbox
    case production

    /// 現在のビルド構成から判定する（#if DEBUG）。
    public static var current: APNsEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}
