import Foundation
import Testing
@testable import SessionFeature

private func makeProtectedFolderWhiteboxTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "phlox-protected-whitebox-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func protectedFolder_whitebox_skipsDescentIntoProtectedChildByStandardizedPath() throws {
    let root = try makeProtectedFolderWhiteboxTempDirectory()
    let protectedChild = root.appending(path: "Pictures")
    try FileManager.default.createDirectory(at: protectedChild, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: protectedChild.appending(path: "photo.jpg").path, contents: Data())
    FileManager.default.createFile(atPath: root.appending(path: "src/photo.swift").path, contents: Data())

    let matches = ComposerSuggestionSources.fileCandidates(
        under: root.path,
        matching: "photo",
        maxDepth: 4,
        maxEntries: 100,
        protectedDirectories: Set([protectedChild.path])
    )

    let insertions = matches.map(\.insertionText)
    #expect(insertions.contains("@src/photo.swift"))
    #expect(!insertions.contains("@Pictures/photo.jpg"))
}

@Test func protectedFolder_whitebox_defaultProtectedDirectoriesUsesUserDomainPaths() {
    let expected: [FileManager.SearchPathDirectory] = [
        .downloadsDirectory, .picturesDirectory, .musicDirectory,
        .desktopDirectory, .documentDirectory, .moviesDirectory,
    ]
    let resolved = Set(expected.compactMap {
        FileManager.default.urls(for: $0, in: .userDomainMask).first?.path
    })

    #expect(!resolved.isEmpty)
    #expect(resolved.isSubset(of: ComposerSuggestionSources.defaultProtectedDirectories))
}
