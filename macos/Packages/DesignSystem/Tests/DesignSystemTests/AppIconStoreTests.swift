import Foundation
import Testing
@testable import DesignSystem

/// suiteName 付き UserDefaults で分離し、共有の UserDefaults.standard を汚さない。
private func withIsolatedDefaults<T>(_ body: (UserDefaults) throws -> T) throws -> T {
    let suiteName = "design-system-app-icon-store-tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    return try body(defaults)
}

@Suite struct AppIconStoreResolutionTests {
    @Test func knownIDResolvesToThatOption() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("white", forKey: AppIconStore.iconKey)
            #expect(AppIconStore.selected(in: defaults).id == "white")
        }
    }

    @Test func unknownIDFallsBackToDefault() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("no-such-icon", forKey: AppIconStore.iconKey)
            #expect(AppIconStore.selected(in: defaults).id == AppIconStore.defaultOption.id)
        }
    }

    @Test func missingValueFallsBackToDefault() throws {
        try withIsolatedDefaults { defaults in
            #expect(AppIconStore.selected(in: defaults).id == AppIconStore.defaultOption.id)
        }
    }

    @Test func defaultOptionIsWhite() {
        #expect(AppIconStore.defaultOption.id == "white")
        #expect(AppIconStore.all.first?.id == "white")
    }

    @Test func allIDsAreUnique() {
        let ids = AppIconStore.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func allAssetNamesAreUnique() {
        let names = AppIconStore.all.map(\.assetName)
        #expect(Set(names).count == names.count)
    }

    @Test func changingSelectionIsReflectedOnNextAccess() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("gradient", forKey: AppIconStore.iconKey)
            #expect(AppIconStore.selected(in: defaults).id == "gradient")
            defaults.set("light", forKey: AppIconStore.iconKey)
            #expect(AppIconStore.selected(in: defaults).id == "light")
        }
    }

    @Test func defaultsDictionaryUsesDefaultID() throws {
        let value = try #require(AppIconStore.defaultsDictionary[AppIconStore.iconKey] as? String)
        #expect(value == AppIconStore.defaultOption.id)
    }
}
