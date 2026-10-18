import Foundation
import Testing
import PhloxCore

struct SessionGlanceTests {
    @Test func symbolsAndLightDarkIslandColors() {
        let expected: [(SessionGlanceState, String?, UInt32, UInt32)] = [
            (.starting, "circle.dashed", 0x3A3A42, 0xD4D4DA),
            (.idle, "pause.circle", 0x56565E, 0xAFAFB6),
            (.running, nil, 0x3A3A42, 0xD4D4DA),
            (.approval, "exclamationmark.shield", 0xA8430A, 0xFFB46E),
            (.question, "questionmark.bubble", 0x1555C0, 0x8DB9FF),
            (.done, "checkmark.circle", 0x1F7A3A, 0x6FD08C),
            (.doneUnread, "checkmark.circle", 0x1F7A3A, 0x6FD08C),
            (.error, "exclamationmark.triangle", 0xB8241C, 0xFF8C82),
            (.stalled, "hourglass", 0x5B3FA8, 0xC9B6FF),
            (.unknown, "questionmark.circle", 0x56565E, 0xAFAFB6),
        ]
        #expect(Set(expected.map { $0.0 }) == Set(SessionGlanceState.allCases))
        for (state, symbol, light, dark) in expected {
            #expect(state.symbolName == symbol)
            #expect(state.foregroundHex(dark: false) == light)
            #expect(state.foregroundHex(dark: true) == dark)
            #expect(state.foregroundHex(dark: false, dynamicIsland: true) == dark)
            #expect(state.foregroundHex(dark: true, dynamicIsland: true) == dark)
        }
    }

    @Test func activityCodesDoNotCreateExitedState() {
        for (code, state) in [
            ("session_completed", SessionGlanceState.done), ("approval_pending", .approval),
            ("question_pending", .question), ("session_error", .error),
            ("session_stalled", .stalled), ("session_exited", .error), ("future", .unknown),
        ] {
            #expect(SessionGlanceState(activityStatus: code) == state)
        }
    }

    @Test func catalogBackgrounds() {
        for (state, light, dark, opacity) in [
            (SessionGlanceState.approval, UInt32(0xFFEBD6), UInt32(0xFF9F0A), 0.22),
            (.question, 0xE3EEFF, 0x0A84FF, 0.24), (.error, 0xFDE7E5, 0xFF453A, 0.22),
            (.stalled, 0xF1ECFB, 0x9678E6, 0.24), (.done, 0xE3F4E8, 0x34C759, 0.20),
        ] {
            #expect(state.background(dark: false).hex == light)
            #expect(state.background(dark: false).opacity == 1)
            #expect(state.background(dark: true).hex == dark)
            #expect(state.background(dark: true).opacity == opacity)
        }
        #expect(SessionGlanceState.allCases.filter(\.hasWidgetFill) == [.approval, .question, .error])
    }

    @Test func oldAndFutureSharedDataRemainReadable() throws {
        let json = """
        [{"id":"old","statusLabel":"Waiting","title":"旧セッション","detail":"Approval required","updatedAt":1000},
         {"id":"future","statusLabel":"future","title":"次版","detail":"","updatedAt":2000,"displayState":"future"}]
        """
        let values = try SharedSessionStore.decode(Data(json.utf8))
        #expect(values[0].displayState == nil)
        #expect(values[0].glanceState == .approval)
        #expect(values[0].updatedAt == Date(timeIntervalSince1970: 1))
        #expect(values[1].glanceState == .unknown)
        #expect(try SharedSessionStore.decode(SharedSessionStore.encode(values)) == values)
    }

    @Test func legacyLabels() {
        for (label, detail, state) in [
            ("Starting", "", SessionGlanceState.starting), ("Running", "", .running),
            ("Finished", "", .done), ("Error", "", .error), ("Waiting", "Ready", .idle),
            ("Waiting", "Approval required", .approval), ("Waiting", "Input required", .question),
            ("new", "", .unknown),
        ] {
            let summary = SharedSessionSummary(id: "old", statusLabel: label, title: "旧", detail: detail, updatedAt: Date())
            #expect(summary.glanceState == state)
        }
    }

    @Test func sharedStorePersistsResolvedStatesAndConfirmedEmpty() throws {
        let suite = "SessionGlanceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedSessionStore(userDefaults: defaults)
        let values = SessionGlanceState.allCases.map {
            SharedSessionSummary(id: $0.rawValue, statusLabel: $0.label, title: "名前", detail: "phlox",
                                 updatedAt: Date(timeIntervalSince1970: 1), displayState: $0.rawValue)
        }
        let writer = SharedSessionWriter(store: store)
        try writer.write(summaries: values)
        #expect(try store.read() == values)
        try writer.write(summaries: [])
        #expect(try store.read().isEmpty)
    }

    @Test func sessionURLRoundTripAndInvalidInputs() throws {
        for id in ["s", "session-123_ABC", String(repeating: "a", count: 128)] {
            let url = try #require(SessionURL.make(sessionID: id))
            #expect(url.absoluteString == "phlox://session/\(id)")
            #expect(SessionURL.sessionID(from: url) == id)
        }
        for id in ["", "a/b", "a b", "日本語", "a?b", String(repeating: "a", count: 129)] {
            #expect(SessionURL.make(sessionID: id) == nil)
        }
        for input in ["https://session/a", "phlox://pair/a", "phlox://session", "phlox://session/",
                      "phlox://session/a/b", "phlox://session/a/", "phlox://session/a?x=1",
                      "phlox://session/a#x", "phlox://user@session/a", "phlox://session:80/a",
                      "phlox://session/%61", "phlox://session/a%2Fb"] {
            #expect(SessionURL.sessionID(from: try #require(URL(string: input))) == nil)
        }
    }
}
