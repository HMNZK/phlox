// task-1 白箱テスト: DefaultSessionBackendPreference の永続化と解決ロジック。

import Foundation
import Testing
@testable import AgentDomain

@Test func defaultSessionBackendPreference_stored_roundTripsChatAndTerminal() {
    let suite = "whitebox-default-backend-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(
        DefaultSessionBackendPreference.chat.rawValue,
        forKey: DefaultSessionBackendPreference.storageKey
    )
    #expect(DefaultSessionBackendPreference.stored(defaults: defaults) == .chat)

    defaults.set(
        DefaultSessionBackendPreference.terminal.rawValue,
        forKey: DefaultSessionBackendPreference.storageKey
    )
    #expect(DefaultSessionBackendPreference.stored(defaults: defaults) == .terminal)
}

@Test func defaultSessionBackendPreference_resolveBackend_coversAllPreferenceCases() {
    #expect(
        DefaultSessionBackendPreference.chat.resolveBackend(supportsStructuredChat: true) == .appServer
    )
    #expect(
        DefaultSessionBackendPreference.chat.resolveBackend(supportsStructuredChat: false) == .pty
    )
    #expect(
        DefaultSessionBackendPreference.terminal.resolveBackend(supportsStructuredChat: true) == .pty
    )
}
