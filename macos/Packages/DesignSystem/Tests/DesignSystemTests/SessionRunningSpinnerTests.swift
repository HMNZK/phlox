import Foundation
import Testing
@testable import DesignSystem

@Test(arguments: [
    (0.0, 0.0), (0.2, 90.0), (0.4, 180.0),
    (0.6, 270.0), (0.8, 0.0), (-0.2, 270.0),
])
func sessionRunningSpinnerRotatesLinearlyEveryEightTenthsOfASecond(sample: (Double, Double)) {
    let angle = SessionRunningSpinner.angle(at: Date(timeIntervalSinceReferenceDate: sample.0))
    #expect(abs(angle - sample.1) < 0.0001)
}
