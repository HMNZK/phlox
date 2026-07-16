import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Test @MainActor
func composerSuggestion_controllerKeepsAllCandidatesInProviderOrder() {
    let many = (0..<20).map {
        SuggestionCandidate(title: "/cmd\($0)", insertionText: "/cmd\($0)", kind: .slashCommand)
    }
    let controller = ComposerSuggestionController(slashProvider: { many }, fileProvider: { _ in [] })

    controller.update(text: "/cmd", cursorUTF16: 4)

    #expect(controller.candidates.map(\.insertionText) == many.map(\.insertionText))
}

@Test func composerSuggestion_fileProvider_isBoundedAndFiltersExcludedDirectories() throws {
    let root = try makeSuggestionTempDirectory()
    try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appending(path: "Sources/Feature"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appending(path: "a/b/c/d/e"), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: root.appending(path: ".git/HiddenFoo.swift").path, contents: Data())
    FileManager.default.createFile(atPath: root.appending(path: "Sources/Feature/FooView.swift").path, contents: Data())
    FileManager.default.createFile(atPath: root.appending(path: "Sources/Feature/OtherFoo.swift").path, contents: Data())
    FileManager.default.createFile(atPath: root.appending(path: "a/b/c/d/e/TooDeepFoo.swift").path, contents: Data())

    let matches = ComposerSuggestionSources.fileCandidates(under: root.path, matching: "Foo", maxDepth: 4, maxEntries: 10)

    #expect(matches.count == 2)
    #expect(matches.map(\.insertionText).contains("@Sources/Feature/FooView.swift"))
    #expect(!matches.map(\.insertionText).contains("@.git/HiddenFoo.swift"))
    #expect(!matches.map(\.insertionText).contains("@a/b/c/d/e/TooDeepFoo.swift"))
}

@Test func composerSuggestion_fileProvider_ordersPrefixBeforeContains() throws {
    let root = try makeSuggestionTempDirectory()
    try FileManager.default.createDirectory(at: root.appending(path: "Sources"), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: root.appending(path: "Sources/OtherFoo.swift").path, contents: Data())
    FileManager.default.createFile(atPath: root.appending(path: "Foo.swift").path, contents: Data())

    let matches = ComposerSuggestionSources.fileCandidates(under: root.path, matching: "Foo")

    #expect(matches.map(\.insertionText).prefix(2) == ["@Foo.swift", "@Sources/OtherFoo.swift"])
}

@Test func composerSuggestion_fileProvider_truncatesMatchingFilesAtMaxEntries() throws {
    let root = try makeSuggestionTempDirectory()
    FileManager.default.createFile(atPath: root.appending(path: "AlphaOne.swift").path, contents: Data())
    FileManager.default.createFile(atPath: root.appending(path: "AlphaThree.swift").path, contents: Data())
    FileManager.default.createFile(atPath: root.appending(path: "AlphaTwo.swift").path, contents: Data())

    let matches = ComposerSuggestionSources.fileCandidates(
        under: root.path,
        matching: "Alpha",
        maxDepth: 4,
        maxEntries: 2
    )

    #expect(matches.count == 2)
}

@Test func composerSuggestion_fileProvider_countsDirectoriesTowardMaxEntries() throws {
    let root = try makeSuggestionTempDirectory()
    for index in 0..<100 {
        try FileManager.default.createDirectory(
            at: root.appending(path: String(format: "empty-%03d", index)),
            withIntermediateDirectories: true
        )
    }
    FileManager.default.createFile(atPath: root.appending(path: "z-last-match.swift").path, contents: Data())

    let matches = ComposerSuggestionSources.fileCandidates(
        under: root.path,
        matching: "last",
        maxDepth: 4,
        maxEntries: 50
    )

    #expect(matches.isEmpty)
}

@Test func composerSuggestion_fileProvider_reusesWorkspaceCacheWithinTTL() throws {
    let root = try makeSuggestionTempDirectory()
    FileManager.default.createFile(atPath: root.appending(path: "CachedOne.swift").path, contents: Data())

    let first = ComposerSuggestionSources.fileCandidates(under: root.path, matching: "CachedOne")
    FileManager.default.createFile(atPath: root.appending(path: "CachedTwo.swift").path, contents: Data())
    let second = ComposerSuggestionSources.fileCandidates(under: root.path, matching: "CachedTwo")

    #expect(first.map(\.insertionText) == ["@CachedOne.swift"])
    #expect(second.isEmpty)
}

@Test func composerSuggestion_slashProvider_reusesWorkspaceCacheWithinTTL() throws {
    let home = try makeSuggestionTempDirectory()
    let workspace = try makeSuggestionTempDirectory()
    try FileManager.default.createDirectory(at: workspace.appending(path: ".claude/commands"), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: workspace.appending(path: ".claude/commands/first.md").path, contents: Data())

    let first = ComposerSuggestionSources.slashCandidates(
        homeDirectory: home,
        workingDirectory: workspace.path
    )
    .map(\.insertionText)
    FileManager.default.createFile(atPath: workspace.appending(path: ".claude/commands/second.md").path, contents: Data())
    let second = ComposerSuggestionSources.slashCandidates(
        homeDirectory: home,
        workingDirectory: workspace.path
    )
    .map(\.insertionText)

    #expect(first.contains("/first"))
    #expect(!first.contains("/second"))
    #expect(!second.contains("/second"))
}

@Test func composerSuggestion_slashProviderCombinesBuiltinsCommandsAndSkills() throws {
    let home = try makeSuggestionTempDirectory()
    let workspace = try makeSuggestionTempDirectory()
    try FileManager.default.createDirectory(at: home.appending(path: ".claude/commands"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: workspace.appending(path: ".claude/commands"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: home.appending(path: ".claude/skills/home-skill"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: workspace.appending(path: ".claude/skills/work-skill"), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: home.appending(path: ".claude/commands/home.md").path, contents: Data())
    FileManager.default.createFile(atPath: workspace.appending(path: ".claude/commands/work.md").path, contents: Data())

    let insertions = ComposerSuggestionSources.slashCandidates(
        homeDirectory: home,
        workingDirectory: workspace.path
    )
    .map(\.insertionText)

    #expect(insertions.contains("/compact"))
    #expect(insertions.contains("/home"))
    #expect(insertions.contains("/work"))
    #expect(insertions.contains("/home-skill"))
    #expect(insertions.contains("/work-skill"))
}

@Test func composerSuggestion_skillSubtitleUsesQuotedDescription() throws {
    let home = try makeSuggestionTempDirectory()
    let workspace = try makeSuggestionTempDirectory()
    let skillDir = home.appending(path: ".claude/skills/quoted-skill", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: quoted-skill
    description: "Quoted helpful thing"
    ---
    # Quoted Skill
    """.write(to: skillDir.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    let skill = try #require(ComposerSuggestionSources.slashCandidates(
        homeDirectory: home,
        workingDirectory: workspace.path
    ).first { $0.insertionText == "/quoted-skill" })

    #expect(skill.subtitle == "Quoted helpful thing")
}

@Test func composerSuggestion_skillSubtitleFallsBackForBlankDescription() throws {
    let home = try makeSuggestionTempDirectory()
    let workspace = try makeSuggestionTempDirectory()
    let skillDir = workspace.appending(path: ".claude/skills/blank-skill", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: blank-skill
    description:
    ---
    # Blank Skill
    """.write(to: skillDir.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    let skill = try #require(ComposerSuggestionSources.slashCandidates(
        homeDirectory: home,
        workingDirectory: workspace.path
    ).first { $0.insertionText == "/blank-skill" })

    #expect(skill.subtitle == "Skill")
}

private func makeSuggestionTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "phlox-composer-suggestion-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
