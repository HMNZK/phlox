import Testing
import ChatRenderKit
@testable import DesignSystemIOS

@Suite("DSReasoningText 白箱")
struct DSReasoningTextWhiteboxTests {
    @Test("表示データは ChatReasoningPresentation と一致する")
    func presentationUsesSharedValue() {
        let text = "  # 調査\n本文  "
        let shared = ChatReasoningPresentation(text: text)
        let presentation = DSReasoningText.presentation(for: text)

        #expect(presentation == shared)
    }

    @Test("開閉表示は共有判定と呼び出し元のトグル有無の両方を満たす")
    func disclosureRequiresSharedRuleAndToggle() {
        #expect(DSReasoningText.showsDisclosure(text: "短い一文", hasToggle: true) == false)
        #expect(DSReasoningText.showsDisclosure(text: "# 見出し\n本文", hasToggle: true) == true)
        #expect(DSReasoningText.showsDisclosure(text: "# 見出し\n本文", hasToggle: false) == false)
    }
}
