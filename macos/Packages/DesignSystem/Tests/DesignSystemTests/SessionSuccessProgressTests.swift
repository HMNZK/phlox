import Foundation
import Testing
@testable import DesignSystem

@Test(arguments: [
    (-0.1, 0.0, 0.0), (0.0, 0.0, 0.0), (0.25, 0.5, 0.0),
    (0.5, 1.0, 0.0), (0.6, 1.0, 0.0), (0.75, 1.0, 0.5),
    (0.9, 1.0, 1.0), (2.0, 1.0, 1.0),
])
func successIndicatorDrawsRingBeforeTick(sample: (Double, Double, Double)) {
    let progress = SessionSuccessProgress.at(elapsed: sample.0)
    #expect(abs(progress.ring - sample.1) < 0.0001)
    #expect(abs(progress.tick - sample.2) < 0.0001)
}
