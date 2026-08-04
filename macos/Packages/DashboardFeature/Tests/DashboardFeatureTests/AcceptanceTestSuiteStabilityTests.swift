import Foundation
import Testing

/// task-7 の受け入れテスト（PM がディスパッチ前に凍結）。
///
/// task-7 は「負荷が掛かると落ちる既存テスト 15 件を、skip・削除・待ち時間の水増しをせずに
/// 決定論化する」タスクである。**安定したかどうか自体はユニットテストで表現できない**
/// （それは verify.sh を 3 連続＋CPU 負荷下で実走する PM のゲートが担う）。
/// ここで凍結するのは、その安定化が**誠実な手段で行われたこと**を機械的に守る不変条件だけである。
///
/// 守る不変条件:
///  1. テストケースが消えていない（`@Test` の数が基準以上）
///  2. アサーションが骨抜きにされていない（`#expect` / `#require` / `confirmation` の合計が基準以上）
///  3. skip・無効化・既知の問題扱い・直列化・時間制限の追加で通していない（弱体化トークンが基準以下）
///  4. 壁時計待ち（`Task.sleep`）を増やしていない（減らす・無くすのは可）
///
/// 基準値は 2026-08-04 の `feature/plan-remediation`（task-7 着手前）の実測値。
/// **正当な理由で基準を下回る／上回る変更が要るなら、実装役はこのファイルを書き換えず PM に報告し、
/// PM が理由を decision-log に記録したうえで再凍結する**（このファイルは task-7 の allowed_paths 外）。
@Suite("Acceptance: test suite stability guard (task-7)")
struct AcceptanceTestSuiteStabilityTests {

    /// 監視対象。パスは `macos/` からの相対。
    struct Baseline {
        let path: String
        /// `@Test` の出現数の下限
        let minTestCases: Int
        /// `#expect` / `#require` / `confirmation` の出現数の合計の下限
        let minAssertions: Int
        /// `.disabled(` / `withKnownIssue` / `XCTSkip` / `.enabled(if` / `.serialized` / `.timeLimit(` の
        /// 出現数の合計の上限
        let maxWeakeningTokens: Int
        /// `Task.sleep` の出現数の上限
        let maxWallClockSleeps: Int
    }

    static let baselines: [Baseline] = [
        Baseline(
            path: "Packages/DashboardFeature/Tests/DashboardFeatureTests/DashboardViewModelTests.swift",
            minTestCases: 96, minAssertions: 329, maxWeakeningTokens: 0, maxWallClockSleeps: 17
        ),
        Baseline(
            path: "Packages/DashboardFeature/Tests/DashboardFeatureTests/SessionViewModelTests.swift",
            minTestCases: 51, minAssertions: 103, maxWeakeningTokens: 0, maxWallClockSleeps: 22
        ),
        Baseline(
            path: "Packages/DashboardFeature/Tests/DashboardFeatureTests/SessionViewModelCharacterizationTests.swift",
            minTestCases: 30, minAssertions: 72, maxWeakeningTokens: 0, maxWallClockSleeps: 2
        ),
        Baseline(
            path: "Packages/DashboardFeature/Tests/DashboardFeatureTests/CursorChatCreatorTests.swift",
            minTestCases: 5, minAssertions: 6, maxWeakeningTokens: 0, maxWallClockSleeps: 0
        ),
        Baseline(
            path: "Packages/DashboardFeature/Tests/DashboardFeatureTests/StructuredPreApprovalWiringTests.swift",
            minTestCases: 10, minAssertions: 34, maxWeakeningTokens: 0, maxWallClockSleeps: 1
        ),
        Baseline(
            path: "Packages/DashboardFeature/Tests/DashboardFeatureTests/UserTerminalControllerWhiteboxTests.swift",
            // 既存の `.timeLimit(.minutes(1))`（スイート単位）が 1 件ある。これ以上増やさない。
            minTestCases: 16, minAssertions: 53, maxWeakeningTokens: 1, maxWallClockSleeps: 3
        ),
        Baseline(
            path: "Packages/DashboardFeature/Tests/DashboardFeatureTests/TerminalPanelViewWhiteboxTests.swift",
            minTestCases: 2, minAssertions: 5, maxWeakeningTokens: 0, maxWallClockSleeps: 1
        ),
        Baseline(
            path: "Packages/SessionFeature/Tests/SessionFeatureTests/MidTurnPersistenceWhiteboxTests.swift",
            minTestCases: 12, minAssertions: 33, maxWeakeningTokens: 0, maxWallClockSleeps: 4
        ),
    ]

    /// `macos/` ディレクトリ。このファイルは
    /// `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/` にあるので 5 段上。
    static var macosDirectory: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url = url.deletingLastPathComponent() }
        return url
    }

    static func occurrences(of patterns: [String], in text: String) -> Int {
        patterns.reduce(0) { total, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return total }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return total + regex.numberOfMatches(in: text, range: range)
        }
    }

    @Test("監視対象のテストファイルがすべて存在する")
    func targetFilesExist() throws {
        for baseline in Self.baselines {
            let url = Self.macosDirectory.appendingPathComponent(baseline.path)
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "task-7 の監視対象が見つからない（削除・移動された可能性がある): \(baseline.path)"
            )
        }
    }

    @Test("テストケースが削除されていない")
    func testCasesNotRemoved() throws {
        for baseline in Self.baselines {
            let source = try String(contentsOf: Self.macosDirectory.appendingPathComponent(baseline.path), encoding: .utf8)
            let count = Self.occurrences(of: ["@Test"], in: source)
            #expect(
                count >= baseline.minTestCases,
                "\(baseline.path): @Test が \(baseline.minTestCases) 件から \(count) 件へ減っている。テストを削除して通してはならない。"
            )
        }
    }

    @Test("アサーションが骨抜きにされていない")
    func assertionsNotWeakened() throws {
        for baseline in Self.baselines {
            let source = try String(contentsOf: Self.macosDirectory.appendingPathComponent(baseline.path), encoding: .utf8)
            let count = Self.occurrences(of: ["#expect", "#require", "confirmation"], in: source)
            #expect(
                count >= baseline.minAssertions,
                "\(baseline.path): #expect/#require/confirmation の合計が \(baseline.minAssertions) から \(count) へ減っている。期待を消して通してはならない。"
            )
        }
    }

    @Test("skip・無効化・直列化・時間制限で通していない")
    func noWeakeningTraitsIntroduced() throws {
        let patterns = [
            #"\.disabled\("#,
            #"withKnownIssue"#,
            #"XCTSkip"#,
            #"\.enabled\(if"#,
            #"\.serialized"#,
            #"\.timeLimit\("#,
        ]
        for baseline in Self.baselines {
            let source = try String(contentsOf: Self.macosDirectory.appendingPathComponent(baseline.path), encoding: .utf8)
            let count = Self.occurrences(of: patterns, in: source)
            #expect(
                count <= baseline.maxWeakeningTokens,
                "\(baseline.path): 弱体化トレイト（disabled/withKnownIssue/XCTSkip/enabled(if/serialized/timeLimit）が \(baseline.maxWeakeningTokens) から \(count) へ増えている。これらは対症療法であり禁止。"
            )
        }
    }

    @Test("壁時計待ち（Task.sleep）を増やしていない")
    func wallClockSleepsNotIncreased() throws {
        for baseline in Self.baselines {
            let source = try String(contentsOf: Self.macosDirectory.appendingPathComponent(baseline.path), encoding: .utf8)
            let count = Self.occurrences(of: [#"Task\.sleep"#], in: source)
            #expect(
                count <= baseline.maxWallClockSleeps,
                "\(baseline.path): Task.sleep が \(baseline.maxWallClockSleeps) から \(count) へ増えている。待ち時間の水増し・ポーリングの追加ではなく、状態変化そのものを待つ形にすること。"
            )
        }
    }
}
