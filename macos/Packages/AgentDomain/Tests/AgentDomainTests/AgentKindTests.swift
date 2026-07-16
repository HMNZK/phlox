import Testing
@testable import AgentDomain

// AgentKind の個数は固定しない(CLI の増減で壊れるため)。
// 網羅性は agentRegistry_containsDescriptorForEveryAgentKind が守る。
@Test func agentKind_binaryNames() {
    #expect(AgentKind.claudeCode.binaryName == "claude")
    #expect(AgentKind.codex.binaryName == "codex")
    #expect(AgentKind.cursor.binaryName == "cursor-agent")
}

@Test func agentKind_displayNamesAndSymbolNamesAreNonEmpty() {
    for kind in AgentKind.allCases {
        #expect(!kind.displayName.isEmpty)
        #expect(!kind.symbolName.isEmpty)
    }
}

@Test func agentRegistry_containsDescriptorForEveryAgentKind() {
    #expect(AgentRegistry.descriptors.count == AgentKind.allCases.count)
    for kind in AgentKind.allCases {
        #expect(AgentRegistry.descriptors[kind] != nil)
    }
}

@Test func agentRegistry_binaryNamesMatchAgentKindAccessors() {
    for kind in AgentKind.allCases {
        #expect(AgentRegistry.descriptor(for: kind).binaryName == kind.binaryName)
    }
}
