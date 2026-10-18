import Testing
import ChatRenderKit
@testable import DesignSystemIOS

@Suite("DSReasoningText 白箱")
struct DSReasoningTextWhiteboxTests {
    @Test("表示データは ChatReasoningPresentation と一致する", arguments: [
        "  # 調査\n本文  ",
        "短い一文",
        "# 見出し\n本文がある",
        "   ",
    ])
    func presentationUsesSharedValue(_ text: String) {
        let shared = ChatReasoningPresentation(text: text)
        let presentation = DSReasoningText.presentation(for: text)

        #expect(presentation == shared)
    }

    @Test("思考カードは本文の長さによらずトグルがあれば開閉できる")
    func disclosureRequiresSharedRuleAndToggle() {
        #expect(DSReasoningText.showsDisclosure(text: "短い一文", hasToggle: true) == true)
        #expect(DSReasoningText.showsDisclosure(text: "# 見出し\n本文", hasToggle: true) == true)
        #expect(DSReasoningText.showsDisclosure(text: "# 見出し\n本文", hasToggle: false) == false)
    }
}
