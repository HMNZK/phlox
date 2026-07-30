import Testing
@testable import ChatRenderKit

@Suite("ChatRenderKit 白箱")
struct ChatRenderKitWhiteboxTests {
    @Test("diff の行順・ID・採番は入力順を保つ")
    func diffClassificationPreservesOrderAndNumbers() {
        let lines = ChatDiffClassifier.classify("@@ -2 +4 @@\n-old\n+new\n context")

        #expect(lines.map(\.id) == [0, 1, 2, 3])
        #expect(lines.map(\.text) == ["@@ -2 +4 @@", "-old", "+new", " context"])
        #expect(lines.map(\.oldLineNumber) == [nil, 2, nil, nil])
        #expect(lines.map(\.newLineNumber) == [nil, nil, 4, 5])
        #expect(lines.map(\.displayLineNumber) == [nil, 2, 4, 5])
    }

    @Test("Swift と shell のトークン連結は原文を保つ")
    func tokenizersPreserveSource() {
        let swift = "let s = \"let func\" // note"
        let shell = "git commit --amend $HOME && echo ok"

        #expect(ChatCodeTokenizer.swift(swift).map(\.text).joined() == swift)
        #expect(ChatCodeTokenizer.shell(shell).map(\.text).joined() == shell)
        #expect(ChatCodeTokenizer.swift(swift).contains { $0.kind == .string && $0.text.contains("let func") })
        #expect(ChatCodeTokenizer.shell(shell).contains { $0.kind == .subcommand && $0.text == "commit" })
    }

    @Test("共有プレゼンテーションは境界値をそのまま扱う")
    func presentationBoundaryValues() {
        let patch = ChatFilePatch(path: "src/Example.swift", diff: "+new\n-old", kind: "edit")
        let reasoning = ChatReasoningPresentation(text: "  # 調査\n本文  ")

        #expect(ChatFileChangePresentation.counts(for: [patch]) == .init(additions: 1, deletions: 1))
        #expect(ChatFileChangePresentation.title(for: [patch]) == "編集済み Example.swift")
        #expect(reasoning.headline == "調査")
        #expect(reasoning.trimmedText == "# 調査\n本文")
        #expect(reasoning.usesDisclosure)
        #expect(ChatCommandGroupTitle.derive(commands: [nil, "  ", "swift test  "], itemCount: 3) == "swift test")
    }
}
