import Testing
@testable import AgentDomain

@Test func agentLaunchSpec_followsNativeSessionIDFromHook_defaultsFalse() {
    let spec = AgentLaunchSpec()
    #expect(spec.followsNativeSessionIDFromHook == false)
}

@Test func agentRegistry_claudeCode_followsNativeSessionIDFromHook() {
    let descriptor = AgentRegistry.descriptor(for: .claudeCode)
    #expect(descriptor.launchSpec.followsNativeSessionIDFromHook == true)
}

@Test func agentRegistry_codex_doesNotFollowNativeSessionIDFromHook() {
    let descriptor = AgentRegistry.descriptor(for: .codex)
    #expect(descriptor.launchSpec.followsNativeSessionIDFromHook == false)
}
