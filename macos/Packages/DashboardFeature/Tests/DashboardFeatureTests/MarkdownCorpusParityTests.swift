import Foundation
import MarkdownUI
import Testing
@testable import DashboardFeature

struct MarkdownCorpusParityTests {
    @Test func corpusRenderingParity() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let roots = ProcessInfo.processInfo.environment["PHLOX_MARKDOWN_CORPUS_ROOTS"]?
            .split(separator: ":").map(String.init) ?? [repository.appendingPathComponent("macos/docs").path]
        var files = 0
        var mismatches: [String] = []
        for root in roots {
            let rootURL = URL(fileURLWithPath: (root as NSString).expandingTildeInPath).resolvingSymlinksInPath()
            let enumerator = try #require(FileManager.default.enumerator(at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))
            while let url = enumerator.nextObject() as? URL {
                if [".build", "node_modules", "DerivedData"].contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                guard ["md", "markdown"].contains(url.pathExtension),
                      (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
                let data = try Data(contentsOf: url)
                guard data.count <= 500_000, var source = String(data: data, encoding: .utf8) else { continue }
                if source.hasPrefix("\u{FEFF}") { source.removeFirst() }
                let analysis = MarkdownBlocks.analyze(source)
                let safe = analysis.isSafe
                #expect(safe, "解析できないファイル: \(url.path)")
                let body = analysis.blocks.first?.kind == .frontMatter
                    ? String(decoding: source.utf8.dropFirst(analysis.blocks[0].range.count), as: UTF8.self) : source
                files += 1
                let joined = MarkdownContent { for block in analysis.blocks { MarkdownContent(block.renderedMarkdown) } }
                if joined.renderHTML() != MarkdownContent(body).renderHTML() {
                    mismatches.append(url.path)
                }
            }
        }
        print("Markdown 描画比較: \(files)件、不一致 \(mismatches.count)件")
        for path in mismatches.prefix(10) { print("不一致: \(path)") }
        #expect(files > 0)
        let mismatchCount = mismatches.count
        #expect(mismatchCount == 0)
    }
}
