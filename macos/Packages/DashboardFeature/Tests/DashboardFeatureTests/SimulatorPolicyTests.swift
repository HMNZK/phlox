import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Suite(.serialized) @MainActor
struct SimulatorPolicyTests {
    @Test func 開く操作と再度開く操作は帯へのフォーカスだけを要求する() async {
        let fixture = HubCatalogFixture(states: ["端末A": "Shutdown"])
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let session = SessionID(), other = SessionID()
        #expect(hub.menuFocusRevision(for: session) == 0)
        hub.requestMenuFocus(for: session)
        #expect(hub.menuFocusRevision(for: session) == 1)
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        hub.requestMenuFocus(for: session)
        #expect(hub.menuFocusRevision(for: session) == 2)
        #expect(hub.menuFocusRevision(for: other) == 0)
        #expect(fake.inputs == 0)
        #expect(await fixture.mutations().isEmpty)
        hub.disconnectAll()
    }

    @Test(arguments: [false, true])
    func タブを開いて表示しても停止端末を起動せず入力しない(booted: Bool) async throws {
        let fixture = HubCatalogFixture(states: ["端末A": booted ? "Booted" : "Shutdown"])
        let fake = HubTransport()
        var creations = 0
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            creations += 1
            return SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let session = SessionID()
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        if booted {
            let connection = try #require(hub.connection(for: session))
            fake.complete(udid: "端末A", generation: connection.generation.current)
        }
        #expect(creations == (booted ? 1 : 0))
        #expect(fake.inputs == 0)
        #expect(await fixture.mutations().isEmpty)
        hub.disconnectAll()
    }
}
