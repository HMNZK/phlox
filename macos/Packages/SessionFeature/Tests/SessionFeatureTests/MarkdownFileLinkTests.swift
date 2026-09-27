import Foundation
import Testing
@testable import SessionFeature

@Test("行番号付きの絶対パスを既存ファイルの URL に変換する")
func markdownFileLinkWithLineNumber() throws {
    let fileURL = URL(fileURLWithPath: #filePath)
    let link = try #require(URL(string: "\(fileURL.path):380"))
    #expect(localMarkdownFileURL(link) == fileURL)
}

@Test("ファイル URL は維持し、存在しないファイルと Web URL は除外する")
func markdownFileLinkValidation() throws {
    let fileURL = URL(fileURLWithPath: #filePath)
    #expect(localMarkdownFileURL(fileURL) == fileURL)
    #expect(localMarkdownFileURL(try #require(URL(string: "/missing-\(UUID().uuidString).swift:3"))) == nil)
    #expect(localMarkdownFileURL(try #require(URL(string: "https://example.com/file.swift"))) == nil)
}
