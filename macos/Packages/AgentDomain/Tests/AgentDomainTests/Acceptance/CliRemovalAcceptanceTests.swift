import Testing
@testable import AgentDomain

// loopflow task-1 の凍結受け入れテスト（実装役は編集禁止）。
// 契約: Gemini / OpenCode / Goose を Phlox から完全除去し、既定 CLI は
// claudeCode / codex / cursor の3種のみとする（tasks/task-1.md）。
//
// 注: 実装前は AgentKind に gemini/opencode/goose が残っているため、この
// テストは red になる（`AgentKind` に .gemini 等が存在する限り集合が一致しない）。
// 実装役は enum ケースと descriptor を削除して green にする。

@Test func cliRemoval_agentKindHasOnlyClaudeCodexCursor() {
    let kinds = Set(AgentKind.allCases)
    #expect(kinds == [.claudeCode, .codex, .cursor])
}

@Test func cliRemoval_registryHasExactlyThreeDescriptors() {
    #expect(AgentRegistry.allDescriptors.count == 3)
    let kinds = Set(AgentRegistry.allDescriptors.map(\.kind))
    #expect(kinds == [.claudeCode, .codex, .cursor])
}

@Test func cliRemoval_noBinaryNamedGeminiOpencodeGoose() {
    let binaries = Set(AgentRegistry.allDescriptors.map(\.binaryName))
    #expect(!binaries.contains("gemini"))
    #expect(!binaries.contains("opencode"))
    #expect(!binaries.contains("goose"))
}
