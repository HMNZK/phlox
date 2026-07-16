import Testing
import DesignSystem
@testable import DashboardFeature
@testable import SessionFeature

@Suite struct SessionGridLayoutTests {
    // MARK: - Auto

    @Test func auto_oneSession() {
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 1) == (1, 1))
    }

    @Test func auto_twoSessions() {
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 2) == (2, 1))
    }

    @Test func auto_threeSessions() {
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 3) == (2, 2))
    }

    @Test func auto_fourSessions() {
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 4) == (2, 2))
    }

    @Test func auto_fiveSessions() {
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 5) == (3, 2))
    }

    @Test func auto_nineSessions() {
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 9) == (3, 3))
    }

    // MARK: - Fixed columns

    @Test func oneColumn_threeSessions() {
        #expect(sessionGridDimensions(columns: .one, sessionCount: 3) == (1, 1))
    }

    @Test func twoColumns_threeSessions() {
        #expect(sessionGridDimensions(columns: .two, sessionCount: 3) == (2, 2))
    }

    @Test func twoColumns_fiveSessions() {
        #expect(sessionGridDimensions(columns: .two, sessionCount: 5) == (2, 2))
    }

    @Test func threeColumns_threeSessions() {
        #expect(sessionGridDimensions(columns: .three, sessionCount: 3) == (3, 3))
    }

    @Test func threeColumns_fiveSessions() {
        #expect(sessionGridDimensions(columns: .three, sessionCount: 5) == (3, 3))
    }

    @Test func fourColumns_sixSessions() {
        #expect(sessionGridDimensions(columns: .four, sessionCount: 6) == (4, 4))
    }

    @Test func fourColumns_eightSessions_divisible() {
        #expect(sessionGridDimensions(columns: .four, sessionCount: 8) == (4, 4))
    }

    @Test func oneColumn_oneSession() {
        #expect(sessionGridDimensions(columns: .one, sessionCount: 1) == (1, 1))
    }

    // MARK: - Fixed columns exceed session count

    @Test func threeColumns_twoSessions() {
        #expect(sessionGridDimensions(columns: .three, sessionCount: 2) == (3, 3))
    }

    @Test func fourColumns_twoSessions() {
        #expect(sessionGridDimensions(columns: .four, sessionCount: 2) == (4, 4))
    }

    // MARK: - Edge cases

    @Test func zeroSessions() {
        #expect(sessionGridDimensions(columns: .auto, sessionCount: 0) == (1, 1))
    }

    // MARK: - GridColumns.fixedCount

    @Test func fixedCount_autoIsNil() {
        #expect(GridColumns.auto.fixedCount == nil)
    }

    @Test func fixedCount_one() {
        #expect(GridColumns.one.fixedCount == 1)
    }

    @Test func fixedCount_four() {
        #expect(GridColumns.four.fixedCount == 4)
    }

    @Test func fixedCount_twoAndThree() {
        #expect(GridColumns.two.fixedCount == 2)
        #expect(GridColumns.three.fixedCount == 3)
    }
}
