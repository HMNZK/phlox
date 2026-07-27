import Foundation
import Testing
@testable import AgentDomain

struct LaunchContextForwardCompatWhiteboxTests {
    @Test func unknownRawValue_decodesAsInteractive() throws {
        let data = Data(#""someFutureContext""#.utf8)

        let decoded = try JSONDecoder().decode(SessionLaunchContext.self, from: data)

        #expect(decoded == .interactive)
    }

    @Test func knownRawValues_roundTripUnchanged() throws {
        for context in [SessionLaunchContext.interactive, .orchestration] {
            let encoded = try JSONEncoder().encode(context)
            let decoded = try JSONDecoder().decode(SessionLaunchContext.self, from: encoded)

            #expect(decoded == context)
        }
    }
}
