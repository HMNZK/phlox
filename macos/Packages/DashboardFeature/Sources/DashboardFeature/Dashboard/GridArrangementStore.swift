import Foundation
import SessionFeature

public struct GridArrangementStore {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    public func save(_ arrangement: SessionGridArrangement, size: Int) {
        guard let data = try? JSONEncoder().encode(arrangement) else { return }
        userDefaults.set(data, forKey: key(size: size))
    }

    public func load(size: Int) -> SessionGridArrangement? {
        guard let data = userDefaults.data(forKey: key(size: size)) else { return nil }
        guard let arrangement = try? JSONDecoder().decode(SessionGridArrangement.self, from: data),
              arrangement.size == size else { return nil }
        return arrangement
    }

    private func key(size: Int) -> String {
        "phlox.grid.arrangement.\(size)"
    }
}
