import SwiftUI

private struct UsageViewModelEnvironmentKey: EnvironmentKey {
    static let defaultValue: UsageViewModel? = nil
}

public extension EnvironmentValues {
    var usageViewModel: UsageViewModel? {
        get { self[UsageViewModelEnvironmentKey.self] }
        set { self[UsageViewModelEnvironmentKey.self] = newValue }
    }
}
