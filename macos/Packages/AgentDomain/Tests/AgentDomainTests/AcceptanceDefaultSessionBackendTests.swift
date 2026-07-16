// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — 新規セッションの既定バックエンド設定（R5）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
@testable import AgentDomain

@Test func acceptance_resolveBackend_chatPreference_supportsChat_isAppServer() {
    #expect(DefaultSessionBackendPreference.chat.resolveBackend(supportsStructuredChat: true) == .appServer)
}

@Test func acceptance_resolveBackend_chatPreference_noChatSupport_fallsBackToPty() {
    #expect(DefaultSessionBackendPreference.chat.resolveBackend(supportsStructuredChat: false) == .pty)
}

@Test func acceptance_resolveBackend_terminalPreference_isAlwaysPty() {
    #expect(DefaultSessionBackendPreference.terminal.resolveBackend(supportsStructuredChat: true) == .pty)
    #expect(DefaultSessionBackendPreference.terminal.resolveBackend(supportsStructuredChat: false) == .pty)
}

@Test func acceptance_stored_defaultsToChatWhenUnset() {
    let suite = "acceptance-default-backend-unset-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(DefaultSessionBackendPreference.stored(defaults: defaults) == .chat)
}

@Test func acceptance_stored_readsPersistedValue() {
    let suite = "acceptance-default-backend-set-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(
        DefaultSessionBackendPreference.terminal.rawValue,
        forKey: DefaultSessionBackendPreference.storageKey
    )
    #expect(DefaultSessionBackendPreference.stored(defaults: defaults) == .terminal)
}

@Test func acceptance_stored_unknownValue_fallsBackToChat() {
    let suite = "acceptance-default-backend-bogus-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("bogus-value", forKey: DefaultSessionBackendPreference.storageKey)
    #expect(DefaultSessionBackendPreference.stored(defaults: defaults) == .chat)
}
