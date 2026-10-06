import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

@Suite("一時的な子タブの保存互換性")
@MainActor
struct SessionTabsPersistenceTests {
    @Test("ブラウザの配置を正規化して旧版でも読める形で保存する")
    func browserLayoutsKeepOldEncoding() throws {
        try checkPersistence(left: .browser, right: nil, focusesRight: false,
                             savedLeft: .conversation, savedRight: nil, savedFocusesRight: false)
        try checkPersistence(left: .browser, right: .terminal, focusesRight: true,
                             savedLeft: .terminal, savedRight: nil, savedFocusesRight: false)
        try checkPersistence(left: .changes, right: .browser, focusesRight: true,
                             savedLeft: .changes, savedRight: nil, savedFocusesRight: false)
        try checkPersistence(left: .browser, right: .simulator, focusesRight: true,
                             savedLeft: .conversation, savedRight: nil, savedFocusesRight: false)
    }
    @Test("左だけがシミュレーターなら保存時に会話へ戻す")
    func simulatorOnLeftWithoutSplit() throws {
        try checkPersistence(left: .simulator, right: nil, focusesRight: false,
                             savedLeft: .conversation, savedRight: nil, savedFocusesRight: false)
    }

    @Test("左がシミュレーターなら保存時に右の端末を左へ昇格する")
    func simulatorOnLeftWithSplit() throws {
        try checkPersistence(left: .simulator, right: .terminal, focusesRight: true,
                             savedLeft: .terminal, savedRight: nil, savedFocusesRight: false)
    }

    @Test("右がシミュレーターなら保存時に分割と右の選択を解除する")
    func simulatorOnRight() throws {
        try checkPersistence(left: .changes, right: .simulator, focusesRight: true,
                             savedLeft: .changes, savedRight: nil, savedFocusesRight: false)
    }

    @Test("隠れているシミュレーターだけを除き既存の分割と幅を保存する")
    func hiddenSimulator() throws {
        try checkPersistence(left: .changes, right: .file("Sources/App.swift"), focusesRight: true,
                             savedLeft: .changes, savedRight: .file("Sources/App.swift"), savedFocusesRight: true)
    }

    @Test("旧データを読み新しい版で保存したデータを旧版で往復できる")
    func oldAndNewSnapshotsRoundTrip() throws {
        let suite = "phlox.tests.sessionTabs.compatibility.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = ProjectID()
        let session = SessionID()
        let closedSession = SessionID()
        var state = ProjectTabState()
        state.order = [closedSession, session]
        state.closed = [closedSession]
        let oldLayout = LegacySessionTabLayout(
            tabs: [.conversation, .terminal, .changes, .file("Sources/App.swift")],
            left: .changes, right: .terminal, focusesRight: true, splitFraction: 0.37
        )
        let original = LegacySessionTabsSnapshot(
            projects: [project: state], sessions: [session: oldLayout, closedSession: oldLayout]
        )
        defaults.set(try JSONEncoder().encode(original), forKey: SessionTabStore.defaultsKey)

        let store = SessionTabStore(defaults: defaults)
        #expect(store.layout(for: session).tabs == [.conversation, .terminal, .changes, .file("Sources/App.swift")])
        #expect(store.layout(for: session).right == .terminal)
        #expect(store.layout(for: session).focusesRight)
        #expect(store.layout(for: session).splitFraction == 0.37)
        #expect(store.snapshot.projects == original.projects)
        store.updateLayout(for: session) { $0.open(.simulator) }

        let data = try #require(defaults.data(forKey: SessionTabStore.defaultsKey))
        let legacy = try JSONDecoder().decode(LegacySessionTabsSnapshot.self, from: data)
        #expect(legacy.sessions[session]?.tabs == oldLayout.tabs)
        #expect(legacy.sessions[session]?.left == .changes)
        #expect(legacy.sessions[session]?.right == nil)
        #expect(legacy.sessions[session]?.focusesRight == false)
        #expect(legacy.sessions[session]?.splitFraction == 0.37)
        #expect(legacy.sessions[closedSession] == oldLayout)
        #expect(legacy.projects == original.projects)

        defaults.set(try JSONEncoder().encode(legacy), forKey: SessionTabStore.defaultsKey)
        let restored = SessionTabStore(defaults: defaults)
        let expected = try JSONDecoder().decode(SessionTabsSnapshot.self, from: data)
        #expect(restored.snapshot == expected)
        #expect(store.layout(for: session).selected == .simulator)
    }

    @Test("既存の子タブの符号化は旧版と同じ")
    func existingCasesKeepEncoding() throws {
        let current: [ChildTab] = [.conversation, .terminal, .changes, .file("Sources/App.swift")]
        let legacy: [LegacyChildTab] = [.conversation, .terminal, .changes, .file("Sources/App.swift")]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let currentData = try encoder.encode(current)
        let legacyData = try encoder.encode(legacy)
        #expect(currentData == legacyData)
    }

    private func checkPersistence(
        left: ChildTab, right: ChildTab?, focusesRight: Bool,
        savedLeft: ChildTab, savedRight: ChildTab?, savedFocusesRight: Bool
    ) throws {
        let suite = "phlox.tests.sessionTabs.simulator.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SessionID()
        var layout = SessionTabLayout()
        layout.tabs = [.conversation, .terminal, .changes, .file("Sources/App.swift"), .simulator, .browser]
        layout.left = left
        layout.right = right
        layout.focusesRight = focusesRight
        layout.splitFraction = 0.37
        let store = SessionTabStore(defaults: defaults)

        store.updateLayout(for: session) { $0 = layout }

        #expect(store.layout(for: session) == layout)
        let data = try #require(defaults.data(forKey: SessionTabStore.defaultsKey))
        let legacy = try JSONDecoder().decode(LegacySessionTabsSnapshot.self, from: data)
        #expect(legacy.sessions[session]?.tabs == [.conversation, .terminal, .changes, .file("Sources/App.swift")])
        let restored = SessionTabStore(defaults: defaults).layout(for: session)
        #expect(restored.tabs == [.conversation, .terminal, .changes, .file("Sources/App.swift")])
        #expect(restored.left == savedLeft)
        #expect(restored.right == savedRight)
        #expect(restored.focusesRight == savedFocusesRight)
        #expect(restored.splitFraction == layout.splitFraction)
    }
}

/// シミュレーターを知らない旧版の合成 Codable と同じ保存形。
private enum LegacyChildTab: Hashable, Codable, Sendable {
    case conversation
    case terminal
    case changes
    case file(String)
}

private struct LegacySessionTabLayout: Codable, Equatable, Sendable {
    var tabs: [LegacyChildTab]
    var left: LegacyChildTab
    var right: LegacyChildTab?
    var focusesRight: Bool
    var splitFraction: Double
}

private struct LegacySessionTabsSnapshot: Codable, Equatable, Sendable {
    var projects: [ProjectID: ProjectTabState]
    var sessions: [SessionID: LegacySessionTabLayout]
}
