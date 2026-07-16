import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@MainActor
private func processingIndicatorCodexVM(
    transport: ScriptedAppServerTransport = ScriptedAppServerTransport()
) -> (ChatSessionViewModel, ScriptedAppServerTransport) {
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-processing-indicator-work"
    )
    return (vm, transport)
}

@Test @MainActor
func processingIndicator_codexIgnoresIdleThreadStatusWhileTurnIsRunning() async throws {
    let (vm, transport) = processingIndicatorCodexVM()

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    try await waitUntil { vm.status == .running }

    transport.receive("""
    {"jsonrpc":"2.0","method":"thread/status/changed","params":{"threadId":"thread-1","status":{"type":"idle"}}}
    """)
    try await Task.sleep(for: .milliseconds(50))

    #expect(vm.status == .running)
}
