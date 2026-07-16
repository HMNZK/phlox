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
