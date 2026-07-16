import Foundation

extension UserDefaults {
    public static func phloxDefaults(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UserDefaults {
        if let suite = environment["PHLOX_DEFAULTS_SUITE"], !suite.isEmpty {
            return UserDefaults(suiteName: suite) ?? .standard
        }
        return .standard
    }
}
