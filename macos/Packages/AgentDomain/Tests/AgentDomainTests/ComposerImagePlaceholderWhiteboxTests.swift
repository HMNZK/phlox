import Foundation
import Testing
@testable import AgentDomain

@Suite("ComposerImagePlaceholder whitebox")
struct ComposerImagePlaceholderWhiteboxTests {

    @Test
    func nextNumber_handlesLargeNumbers() {
        #expect(ComposerImagePlaceholder.nextNumber(after: [99]) == 100)
        #expect(ComposerImagePlaceholder.nextNumber(after: [1, 100]) == 101)
    }

    @Test
    func inserting_doesNotTrimOrNormalizeText() {
        let original = "  hello  "
        let result = ComposerImagePlaceholder.inserting(number: 1, into: original, cursorUTF16: 0)
        // 先頭は lead なし。直後が空白のため trail もなし。
        #expect(result.text == "[Image #1]  hello  ")
    }

    @Test
    func removing_collapsesSpaceAfterTabBeforeToken() {
        // タブは Rule A の「直前が空白」に該当するため、直後の半角スペースは畳まれる。
        #expect(ComposerImagePlaceholder.removing(number: 1, from: "a\t[Image #1] b") == "a\tb")
    }

    @Test
    func characterBoundaryIndex_roundsDownWithinCombiningSequence() {
        // "e\u{0301}" (é as e + combining acute) is one composed character in UTF-16 length 2.
        let composed = "e\u{0301}x"
        let midOffset = 1
        let result = ComposerImagePlaceholder.inserting(number: 1, into: composed, cursorUTF16: midOffset)
        #expect(result.text == "[Image #1] e\u{0301}x")
    }
}
