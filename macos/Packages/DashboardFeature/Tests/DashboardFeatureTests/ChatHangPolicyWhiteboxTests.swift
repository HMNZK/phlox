import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Test func chatHangPolicy_whitebox_clampsNegativeElapsedAndSilence() {
    let start = Date(timeIntervalSince1970: 1_000)
    let futureEvent = Date(timeIntervalSince1970: 1_100)
    let now = Date(timeIntervalSince1970: 990)

    let assessment = ChatHangPolicy.assess(
        now: now,
        turnStartedAt: start,
        lastEventAt: futureEvent,
        warnAfter: 120
    )

    #expect(assessment.elapsed == 0)
    #expect(assessment.silence == 0)
    #expect(assessment.isStalled == false)
}

@Test func chatHangPolicy_whitebox_warnAfterZeroStallsImmediately() {
    let start = Date(timeIntervalSince1970: 1_000)

    let assessment = ChatHangPolicy.assess(
        now: start,
        turnStartedAt: start,
        lastEventAt: nil,
        warnAfter: 0
    )

    #expect(assessment == ChatHangAssessment(elapsed: 0, silence: 0, isStalled: true))
}
