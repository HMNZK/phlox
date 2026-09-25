import Foundation
import Testing

// C-66: 12 Design System の段と同じ大きさの文字は、直書きせず `DSFont` のトークンを通す。
// 段の外の大きさ（部品の見本にある 11.5 Regular・10.5 など）は C-67 の決定で画面ごとに残すので、ここでは見ない。
@Suite("Font token usage")
struct FontTokenUsageTests {
    private static let macosRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // DesignSystemTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // DesignSystem
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // macos

    /// 太さを問わず段の値の大きさ（Regular の段）と、太さも決まっている段。
    private static let regularTiers: Set<Double> = [13, 12.5, 12, 11]
    private static let weightedTiers: [Double: String] = [24: ".bold", 17: ".bold", 14: ".semibold", 11.5: ".semibold"]

    @Test
    func scaleSizesGoThroughTokens() throws {
        // 太さは `.semibold` のほか `isX ? .semibold : .regular` のような式も拾う（`design: .default` は付いていても同じ）。
        let system = try NSRegularExpression(pattern: #"(?<![\w.])(?:Font)?\.system\(size:\s*([0-9.]+)(?:,\s*weight:\s*([^,()]+?))?(?:,\s*design:\s*\.default)?\s*\)"#)
        // 等幅 11 は `DSFont.monoCaption`（太さ付きも）。
        let monoCaption = try NSRegularExpression(pattern: #"(?<![\w.])(?:Font)?\.system\(size:\s*11(?:\.0)?,\s*(?:weight:\s*[^,()]+?,\s*)?design:\s*\.monospaced\s*\)"#)
        var offenders: [String] = []
        var scanned = 0
        for directory in ["App", "Packages"] {
            let base = Self.macosRoot.appendingPathComponent(directory)
            let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" && !$0.path.contains("/Tests/") && !$0.path.contains("/.build/") } ?? []
            for file in files where file.lastPathComponent != "Tokens.swift" {
                // 行頭が // のコメント行は見ない。
                let text = try String(contentsOf: file, encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")
                scanned += 1
                let range = NSRange(text.startIndex..., in: text)
                func report(_ match: NSTextCheckingResult) {
                    offenders.append("\(file.lastPathComponent): \(text[Range(match.range, in: text)!])")
                }
                for match in system.matches(in: text, range: range) {
                    // 13 と 13.0 を同じに扱う。
                    guard let size = Double(text[Range(match.range(at: 1), in: text)!]) else { continue }
                    let weight = Range(match.range(at: 2), in: text).map { text[$0].trimmingCharacters(in: .whitespaces) }
                    if Self.regularTiers.contains(size) || (weight != nil && Self.weightedTiers[size] == weight) {
                        report(match)
                    }
                }
                monoCaption.matches(in: text, range: range).forEach(report)
            }
        }
        // 読めていないと何も見ずに通ってしまうので、読んだ数も確かめる。
        #expect(scanned > 100, "読んだファイル: \(scanned)（\(Self.macosRoot.path)）")
        #expect(offenders.isEmpty, "DSFont のトークンを使う: \(offenders)")
    }
}
