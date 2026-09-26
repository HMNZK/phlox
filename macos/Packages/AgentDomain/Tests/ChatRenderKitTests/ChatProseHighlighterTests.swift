import Testing
@testable import ChatRenderKit

/// 会話の本文で強調する部分（2026-09-26 ユーザー依頼: docs/specs/Chat Screen.dc.html の見本に合わせる）。
@Suite("ChatRenderKit: 本文の強調")
struct ChatProseHighlighterTests {
    private func found(_ text: String) -> [String: ChatProseSpanKind] {
        Dictionary(ChatProseHighlighter.spans(in: text).map { (String(text[$0.range]), $0.kind) }, uniquingKeysWith: { a, _ in a })
    }

    @Test("日本語に接したコード上の名前・ファイル名・. で始まる名前を拾う")
    func codeNamesNextToJapanese() {
        let k = found("expiresAtをChatApprovalRequestに追加し、期限切れを .expired に移す。ApprovalBrokerTests.swiftも更新")
        #expect(k["expiresAt"] == .identifier)
        #expect(k["ChatApprovalRequest"] == .identifier)
        #expect(k[".expired"] == .member)
        #expect(k["ApprovalBrokerTests.swift"] == .file)
    }

    @Test("成功・失敗・増減・数量を拾う")
    func outcomesAndQuantities() {
        let k = found("テストはすべて成功、1 件失敗。+42 −6、既定 10 分")
        #expect(k["すべて成功"] == .success)
        #expect(k["失敗"] == .failure)
        #expect(k["+42"] == .success)
        #expect(k["−6"] == .failure)
        #expect(k["1 件"] == .quantity)
        #expect(k["10 分"] == .quantity)
    }

    @Test("ふつうの英単語・略語・呼び出しだけの名前は強調しない")
    func plainWordsStayPlain() {
        #expect(ChatProseHighlighter.spans(in: "requests() で API と DTO を返す。Swift UI").isEmpty)
    }
}
