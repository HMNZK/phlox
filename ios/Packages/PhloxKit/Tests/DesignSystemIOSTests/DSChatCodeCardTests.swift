import SwiftUI
import Testing
@testable import DesignSystemIOS

@Suite("DSChatCodeCard")
@MainActor
struct DSChatCodeCardTests {
    @Test("カードの寸法は iOS のカードトークンへ委譲する")
    func metricsUseMobileTokens() {
        let card = DSChatCodeCard {
            Text("Bash")
        } content: {
            Text("$ swift test")
        }

        _ = card.body
        #expect(DSChatCodeCardMetrics.cornerRadius == DSRadius.card)
        #expect(DSChatCodeCardMetrics.borderWidth == 1)
    }
}
