// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — @ ファイル補完の再帰列挙が TCC 保護フォルダへ降下しない。
// 判定は「名前一致」ではなく「絶対パス一致」。ルート自体が保護フォルダの場合は走査する。

import Foundation
import Testing
@testable import SessionFeature

private func makeProtectedFolderTempDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "phlox-protected-folder-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func protectedFolder_descendIsSkippedByPathMatch() throws {
    let root = try makeProtectedFolderTempDirectory()
    let downloads = root.appending(path: "Downloads")
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appending(path: "Docs"), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: downloads.appending(path: "Report.pdf").path, contents: Data())
    FileManager.default.createFile(atPath: root.appending(path: "Docs/Report.md").path, contents: Data())

    let matches = ComposerSuggestionSources.fileCandidates(
        under: root.path,
        matching: "Report",
        maxDepth: 4,
        maxEntries: 100,
        protectedDirectories: [downloads.path]
    )

    let insertions = matches.map(\.insertionText)
    #expect(insertions.contains("@Docs/Report.md"))
    #expect(!insertions.contains("@Downloads/Report.pdf"))
}

@Test func protectedFolder_sameNameOutsideProtectedPathIsStillScanned() throws {
    let root = try makeProtectedFolderTempDirectory()
    // 保護パスは「別の場所の Downloads」。プロジェクト内の Sub/Downloads は名前が同じでも走査する。
    let unrelatedProtected = FileManager.default.temporaryDirectory
        .appending(path: "phlox-protected-elsewhere-\(UUID().uuidString)/Downloads")
    try FileManager.default.createDirectory(
        at: root.appending(path: "Sub/Downloads"),
        withIntermediateDirectories: true
    )
    FileManager.default.createFile(
        atPath: root.appending(path: "Sub/Downloads/Notes.md").path,
        contents: Data()
    )

    let matches = ComposerSuggestionSources.fileCandidates(
        under: root.path,
        matching: "Notes",
        maxDepth: 4,
        maxEntries: 100,
        protectedDirectories: [unrelatedProtected.path]
    )

    #expect(matches.map(\.insertionText).contains("@Sub/Downloads/Notes.md"))
}

@Test func protectedFolder_rootItselfProtectedIsStillScanned() throws {
    let root = try makeProtectedFolderTempDirectory()
    FileManager.default.createFile(atPath: root.appending(path: "Direct.swift").path, contents: Data())

    let matches = ComposerSuggestionSources.fileCandidates(
        under: root.path,
        matching: "Direct",
        maxDepth: 4,
        maxEntries: 100,
        protectedDirectories: [root.path]
    )

    #expect(matches.map(\.insertionText).contains("@Direct.swift"))
}

@Test func protectedFolder_defaultSetCoversUserProtectedFolders() {
    let expected: [FileManager.SearchPathDirectory] = [
        .downloadsDirectory, .picturesDirectory, .musicDirectory,
        .desktopDirectory, .documentDirectory, .moviesDirectory,
    ]
    let resolved = expected.compactMap {
        FileManager.default.urls(for: $0, in: .userDomainMask).first?.path
    }

    let defaults = ComposerSuggestionSources.defaultProtectedDirectories

    #expect(!resolved.isEmpty)
    for path in resolved {
        #expect(defaults.contains(path), "defaultProtectedDirectories should contain \(path)")
    }
}
