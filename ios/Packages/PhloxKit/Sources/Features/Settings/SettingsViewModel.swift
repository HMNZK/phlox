import Foundation

@MainActor
@Observable
public final class SettingsViewModel {
    public let settings: AppSettings
    public let appName: String
    public let version: String

    public init(settings: AppSettings, bundle: Bundle = .main) {
        self.settings = settings
        self.appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Phlox"

        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        self.version = build.map { "\(shortVersion) (\($0))" } ?? shortVersion
    }
}
