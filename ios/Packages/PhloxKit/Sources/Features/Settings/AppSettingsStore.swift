import Foundation

public protocol AppSettingsStoring: AnyObject {
    var faceIDEnabled: Bool { get set }
    var notificationsEnabled: Bool { get set }
    var appearance: AppearancePreference { get set }
}

public final class UserDefaultsAppSettingsStore: AppSettingsStoring {
    static let faceIDEnabledKey = "phlox.settings.faceIDEnabled"
    static let notificationsEnabledKey = "phlox.settings.notificationsEnabled"
    static let appearanceKey = "phlox.settings.appearance"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var faceIDEnabled: Bool {
        // wave-7: 顔認証は既定オフ。未設定（新規インストール）時はロックしない。
        get { defaults.object(forKey: Self.faceIDEnabledKey) == nil ? false : defaults.bool(forKey: Self.faceIDEnabledKey) }
        set { defaults.set(newValue, forKey: Self.faceIDEnabledKey) }
    }

    public var notificationsEnabled: Bool {
        get { defaults.object(forKey: Self.notificationsEnabledKey) == nil ? true : defaults.bool(forKey: Self.notificationsEnabledKey) }
        set { defaults.set(newValue, forKey: Self.notificationsEnabledKey) }
    }

    public var appearance: AppearancePreference {
        get {
            guard let rawValue = defaults.string(forKey: Self.appearanceKey) else { return .system }
            return AppearancePreference(rawValue: rawValue) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Self.appearanceKey) }
    }
}

public final class InMemoryAppSettingsStore: AppSettingsStoring {
    public var faceIDEnabled: Bool
    public var notificationsEnabled: Bool
    public var appearance: AppearancePreference

    public init(
        faceIDEnabled: Bool = true,
        notificationsEnabled: Bool = true,
        appearance: AppearancePreference = .system
    ) {
        self.faceIDEnabled = faceIDEnabled
        self.notificationsEnabled = notificationsEnabled
        self.appearance = appearance
    }
}

@MainActor
@Observable
public final class AppSettings {
    public var faceIDEnabled: Bool {
        didSet { store.faceIDEnabled = faceIDEnabled }
    }

    public var notificationsEnabled: Bool {
        didSet { store.notificationsEnabled = notificationsEnabled }
    }

    public var appearance: AppearancePreference {
        didSet { store.appearance = appearance }
    }

    private let store: AppSettingsStoring

    public init(store: AppSettingsStoring) {
        self.store = store
        self.faceIDEnabled = store.faceIDEnabled
        self.notificationsEnabled = store.notificationsEnabled
        self.appearance = store.appearance
    }
}

public enum NotificationRegistrationPolicy {
    public static func shouldRegister(notificationsEnabled: Bool) -> Bool {
        notificationsEnabled
    }
}
