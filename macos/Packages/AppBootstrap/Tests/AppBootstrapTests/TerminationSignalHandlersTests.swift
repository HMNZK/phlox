import Foundation
import Testing
@testable import AppBootstrap

@Suite struct TerminationSignalHandlersTests {
    @Test func installWithNoSignalsReturnsNoSources() {
        let sources = TerminationSignalHandlers.install(
            signals: [],
            queue: DispatchQueue(label: "test.signal.empty"),
            handler: {}
        )

        #expect(sources.isEmpty)
    }
}
