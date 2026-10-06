import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Test
func markdownFormatterSplitsFencedCodeBlocks() {
    let blocks = ChatMarkdownFormatter.splitFencedCodeBlocks("""
    Before `inline`
    ```swift
    let value = 1
    ```
    After
    """)

    #expect(blocks == [
        .markdown("Before `inline`"),
        .code(language: "swift", text: "let value = 1"),
        .markdown("After"),
    ])
}

@Test
func markdownFormatterTreatsUnclosedFenceAsMarkdown() {
    let blocks = ChatMarkdownFormatter.splitFencedCodeBlocks("""
    Before
    ```json
    {"ok": true}
    """)

    #expect(blocks == [
        .markdown("Before"),
        .markdown("``` json\n{\"ok\": true}"),
    ])
}

@Test
func diffLineClassifierClassifiesUnifiedDiffLines() {
    let lines = DiffLineClassifier.classify("""
    diff --git a/A.swift b/A.swift
    --- a/A.swift
    +++ b/A.swift
    @@ -1,2 +1,2 @@
    -old
    +new
     context
    """)

    #expect(lines.map(\.kind) == [
        .fileHeader,
        .fileHeader,
        .fileHeader,
        .hunk,
        .deletion,
        .addition,
        .context,
    ])
}

@Test
func diffLineClassifierClassifiesDeleteToolDiffLinesAsDeletion() {
    let lines = DiffLineClassifier.classify("""
    --- a//work/victim.txt
    +++ b//work/victim.txt
    -hello world
    -second line
    """)

    #expect(lines.map(\.kind) == [
        .fileHeader,
        .fileHeader,
        .deletion,
        .deletion,
    ])
}

// command == nil の commandExecution は "Command: " の空行を出力しない。
@Test
func plainText_commandExecutionWithNilCommand_hasNoEmptyCommandLine() {
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let withOutput = ChatItem.commandExecution(
        id: "c1", command: nil, output: "hello", timestamp: timestamp
    )
    #expect(withOutput.plainText == "hello", "command==nil で 'Command: ' 行が混入: \(withOutput.plainText)")

    let empty = ChatItem.commandExecution(
        id: "c2", command: nil, output: "", timestamp: timestamp
    )
    #expect(empty.plainText.isEmpty, "command==nil・output 空で残骸が出力される: '\(empty.plainText)'")

    // command がある場合は従来どおり。
    let withCommand = ChatItem.commandExecution(
        id: "c3", command: "ls", output: "a.txt", timestamp: timestamp
    )
    #expect(withCommand.plainText == "Command: ls\na.txt")
}
