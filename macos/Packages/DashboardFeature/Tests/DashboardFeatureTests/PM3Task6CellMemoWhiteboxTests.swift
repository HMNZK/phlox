import Foundation
import SwiftUI
import DesignSystem
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-6 白箱（実装役著述）。受け入れテスト（PM 著・編集禁止）が担う外形同値に加え、
// 名指しハザードを内部経路で捕まえる:
//   H1 キャッシュキーの stale ヒット（ストリーミング伸長 / 同長別内容）
//   H2 メモ化が実際に効く（同一内容の再計算が走らない = compute miss が1回）
//   H3 AttributedString run 結合で属性境界（色切替点）が1文字もズレない
// 直列化: 共有グローバルキャッシュの miss カウンタを観測するため、他テストと分離する。
@Suite(.serialized)
struct PM3Task6CellMemoWhiteboxTests {

    // MARK: - H3: 属性境界の完全一致（1文字連結の廃止で色切替点がズレていないこと）

    /// メモ化・run 結合後の highlight が、元アルゴリズム（1文字ずつ append）と1ビットも違わないこと。
    /// 参照実装は監査前の literal 実装をそのまま写経したもの。敵対的入力で境界のズレを炙り出す。
    @Test
    func highlight_matchesCharByCharReferenceExactly() {
        let samples: [String] = [
            "",
            " ",
            "let x = 42",
            "let x=42;var y = 3.14  // 末尾コメント",
            "func f() { return \"a\\\"b\\\\c\" } // done",
            "a+b-c*d/e%f = (g && h) || !i   // ops",
            "identifier123 _under 0xFF 3.14.15 mix",
            "/ not a comment / still not // now comment\nnext line 7",
            "\"unterminated string with // and 42 inside",
            "日本語 identifier 変数 = \"文字列\" // コメント 42",
            "\t\ttabs and    spaces\n\nblank lines\n42",
            "struct S { var n = 0 }\nenum E { case a }",
        ]
        for code in samples {
            let actual = ChatCodeHighlighter.highlight(code)
            let reference = Self.referenceHighlight(code)
            #expect(actual == reference, "色切替点がズレている: \(code.debugDescription)")
            // 文字は完全保存（色属性のみ）。
            #expect(String(actual.characters) == code)
        }
    }

    /// 属性境界が「色ごとにまとまった run」になっているか（1文字連結でないことの積極的検証）。
    /// "let x = 42" は keyword('let') → primary(' x = ') → number('42') の3 run に凝集する。
    @Test
    func highlight_coalescesSameColorIntoSingleRun() {
        let out = ChatCodeHighlighter.highlight("let x = 42")
        // 色付き run が過剰に分割されていない（primary の ' x = ' が1文字ずつ割れていない）。
        let runCount = out.runs.reduce(0) { count, _ in count + 1 }
        #expect(runCount == 3, "同色連結が効いていない（run 数=\(runCount)）")
    }

    // MARK: - H1: キャッシュキーの stale ヒット

    /// ストリーミング伸長のシミュレーション: 同一 item を模した本文が1文字ずつ伸びるとき、
    /// 各段階の highlight は「その段階の本文」を返す（前段階の短い本文＝stale を返さない）。
    @Test
    func highlight_streamingGrowthNeverReturnsStalePrefix() {
        let full = "let greeting = \"hello world\" // 42 friends"
        var built = ""
        for ch in full {
            built.append(ch)
            let out = ChatCodeHighlighter.highlight(built)
            #expect(String(out.characters) == built, "ストリーミング途中で stale（別長さ）を返した")
        }
    }

    /// 同じ長さの別内容を取り違えない（"id＋長さ"キーの stale ヒットを排除できているか）。
    @Test
    func highlight_sameLengthDifferentContentNotConfused() {
        let a = "let value = 1"
        let b = "var value = 2"
        #expect(a.count == b.count)
        let ra = ChatCodeHighlighter.highlight(a)
        let rb = ChatCodeHighlighter.highlight(b)
        #expect(String(ra.characters) == a)
        #expect(String(rb.characters) == b)
        #expect(ra != rb, "同長別内容で同一結果（stale ヒット）")
        // 逆順でもう一度: b→a の順で呼んでも取り違えない。
        #expect(String(ChatCodeHighlighter.highlight(b).characters) == b)
        #expect(String(ChatCodeHighlighter.highlight(a).characters) == a)
    }

    // MARK: - H2: メモ化が実際に効く（内容同一キーで2回目が再計算されない）

    @Test
    func highlight_memoizesByContent_secondCallDoesNotRecompute() {
        let unique = "let token_\(UUID().uuidString) = 1 // \(UUID().uuidString)"
        let before = ChatMessageRenderCache.highlightCache.missCount
        _ = ChatCodeHighlighter.highlight(unique)
        let afterFirst = ChatMessageRenderCache.highlightCache.missCount
        _ = ChatCodeHighlighter.highlight(unique)
        let afterSecond = ChatMessageRenderCache.highlightCache.missCount
        #expect(afterFirst == before + 1, "初回はキャッシュミス（compute）1回のはず")
        #expect(afterSecond == afterFirst, "2回目が再計算された（メモ化が効いていない）")
    }

    @Test
    func markdownBlocks_memoizesByContent_andEqualsPureFunction() {
        let unique = "前文 \(UUID().uuidString)\n```swift\nlet a = 1\n```\n後文"
        let pure = ChatMarkdownFormatter.splitFencedCodeBlocks(unique)
        let before = ChatMessageRenderCache.markdownCache.missCount
        let first = ChatMessageRenderCache.markdownBlocks(unique)
        let afterFirst = ChatMessageRenderCache.markdownCache.missCount
        let second = ChatMessageRenderCache.markdownBlocks(unique)
        let afterSecond = ChatMessageRenderCache.markdownCache.missCount
        #expect(first == pure, "メモ化結果が純関数と不一致")
        #expect(second == pure)
        #expect(afterFirst == before + 1)
        #expect(afterSecond == afterFirst, "2回目が再計算された")
    }

    @Test
    func diffLines_memoizesByContent_andEqualsPureFunction() {
        let unique = "@@ -1,1 +1,1 @@\n-old \(UUID().uuidString)\n+new \(UUID().uuidString)\n context"
        let pure = DiffLineClassifier.classify(unique)
        let before = ChatMessageRenderCache.diffCache.missCount
        let first = ChatMessageRenderCache.diffLines(unique)
        let afterFirst = ChatMessageRenderCache.diffCache.missCount
        let second = ChatMessageRenderCache.diffLines(unique)
        let afterSecond = ChatMessageRenderCache.diffCache.missCount
        #expect(first == pure, "メモ化結果が純関数と不一致")
        #expect(second == pure)
        #expect(afterFirst == before + 1)
        #expect(afterSecond == afterFirst, "2回目が再計算された")
    }

    // MARK: - P4 ポリシー: 閾値境界の単調性（既定折りたたみ）

    @Test
    func fileChangeDisplayPolicy_boundaryIsMonotonic() {
        let t = FileChangeDisplayPolicy.collapseThresholdLines
        let limit = FileChangeDisplayPolicy.visibleLineLimit
        #expect((50...400).contains(t))
        #expect((100...2000).contains(limit))
        #expect(FileChangeDisplayPolicy.defaultExpanded(lineCount: 0) == true)
        #expect(FileChangeDisplayPolicy.defaultExpanded(lineCount: t) == true)
        #expect(FileChangeDisplayPolicy.defaultExpanded(lineCount: t + 1) == false)
        #expect(FileChangeDisplayPolicy.defaultExpanded(lineCount: Int.max) == false)
    }

    // MARK: - ステージ2差し戻し: 展開状態の導出が同一 id 内の diff 置換（行数変化）に追随すること

    /// userOverride=nil のとき、行数変化で既定判定が追随する。
    /// 「小さい started diff → 大きい completed diff」を同一 item.id で置換しても既定折りたたみが効く根拠。
    @Test
    func expansionDerivation_followsLineCountWhenNotOverridden() {
        let small = 5
        let large = 1000
        // 同じ override=nil でも行数が変われば導出結果が変わる（＝行数に追随している）。
        #expect(FileChangeDisplayPolicy.isExpanded(userOverride: nil, lineCount: small) == true)
        #expect(FileChangeDisplayPolicy.isExpanded(userOverride: nil, lineCount: large) == false)
        // 閾値境界でも単調。
        let t = FileChangeDisplayPolicy.collapseThresholdLines
        #expect(FileChangeDisplayPolicy.isExpanded(userOverride: nil, lineCount: t) == true)
        #expect(FileChangeDisplayPolicy.isExpanded(userOverride: nil, lineCount: t + 1) == false)
    }

    /// override 済みならユーザー意思を尊重し、行数が変わっても追随しない。
    @Test
    func expansionDerivation_respectsUserOverrideRegardlessOfLineCount() {
        // 明示的に開いた → 大きい diff でも開いたまま。
        #expect(FileChangeDisplayPolicy.isExpanded(userOverride: true, lineCount: 1000) == true)
        #expect(FileChangeDisplayPolicy.isExpanded(userOverride: true, lineCount: 5) == true)
        // 明示的に閉じた → 小さい diff でも閉じたまま。
        #expect(FileChangeDisplayPolicy.isExpanded(userOverride: false, lineCount: 5) == false)
        #expect(FileChangeDisplayPolicy.isExpanded(userOverride: false, lineCount: 1000) == false)
    }

    // MARK: - 参照実装（監査前の literal highlight の写経・変更禁止）

    private static let referenceKeywords: Set<String> = [
        "actor", "as", "async", "await", "break", "case", "catch", "class", "continue", "default",
        "defer", "do", "else", "enum", "false", "for", "func", "guard", "if", "import", "in",
        "init", "let", "nil", "private", "public", "return", "self", "static", "struct", "switch",
        "throw", "throws", "true", "try", "var", "while",
    ]

    private static func referenceHighlight(_ code: String) -> AttributedString {
        var output = AttributedString()
        var index = code.startIndex

        func append(_ string: String, color: Color) {
            var chunk = AttributedString(string)
            chunk.foregroundColor = color
            output += chunk
        }

        while index < code.endIndex {
            if code[index] == "/", code.index(after: index) < code.endIndex, code[code.index(after: index)] == "/" {
                let end = code[index...].firstIndex(of: "\n") ?? code.endIndex
                append(String(code[index..<end]), color: DSColor.codeSyntaxComment)
                index = end
                continue
            }

            if code[index] == "\"" {
                var end = code.index(after: index)
                var escaped = false
                while end < code.endIndex {
                    let character = code[end]
                    if character == "\"" && !escaped {
                        end = code.index(after: end)
                        break
                    }
                    escaped = character == "\\" && !escaped
                    if character != "\\" {
                        escaped = false
                    }
                    end = code.index(after: end)
                }
                append(String(code[index..<end]), color: DSColor.codeSyntaxString)
                index = end
                continue
            }

            if code[index].isNumber {
                let end = code[index...].firstIndex { !$0.isNumber && $0 != "." } ?? code.endIndex
                append(String(code[index..<end]), color: DSColor.codeSyntaxNumber)
                index = end
                continue
            }

            if code[index].isLetter || code[index] == "_" {
                let end = code[index...].firstIndex { !$0.isLetter && !$0.isNumber && $0 != "_" } ?? code.endIndex
                let word = String(code[index..<end])
                append(word, color: referenceKeywords.contains(word) ? DSColor.codeSyntaxKeyword : DSColor.chatTextPrimary)
                index = end
                continue
            }

            append(String(code[index]), color: DSColor.chatTextPrimary)
            index = code.index(after: index)
        }

        return output
    }
}
