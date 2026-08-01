// 契約の正本: tasks/task-5.md — Codex の質問の `isSecret`（伏せ字入力）に対応する。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。

import Foundation
import Testing
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

/// 製品コードのソースを読む（描画の分岐を機械判定するため。同種の白箱検査が
/// UserQuestionFocusWhiteboxTests に既にある）。
private func source(of fileName: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SessionFeatureTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // SessionFeature(package root)
        .appendingPathComponent("Sources/SessionFeature/\(fileName)")
    return try String(contentsOf: url, encoding: .utf8)
}

private actor Captured {
    private var value: ChatUserInputRequest?
    func set(_ request: ChatUserInputRequest) { if value == nil { value = request } }
    var current: ChatUserInputRequest? { value }
}

private func codexRequest(isSecret: Bool?) -> ToolRequestUserInputRequest {
    ToolRequestUserInputRequest(
        threadId: "t",
        turnId: "u",
        itemId: "i",
        questions: [
            ToolRequestUserInputQuestion(
                id: "q1",
                header: "認証",
                question: "API キーを入力してください",
                options: nil,
                isOther: nil,
                isSecret: isSecret
            )
        ]
    )
}

/// broker へ質問を投げ、橋渡しされた `ChatUserQuestion` を1件受け取る。
private func bridgedQuestion(isSecret: Bool?) async -> ChatUserQuestion? {
    let broker = ChatApprovalBroker()
    let handler = broker.serverRequestHandler
    let captured = Captured()

    let stream = await broker.userInputRequests
    let collector = Task {
        for await request in stream {
            await captured.set(request)
            return
        }
    }
    Task { _ = try? await handler(.userInputRequest(codexRequest(isSecret: isSecret))) }

    var elapsed: UInt64 = 0
    while elapsed < 2_000_000_000 {
        if let request = await captured.current {
            collector.cancel()
            await broker.cancelAll()
            return request.questions.first
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        elapsed += 20_000_000
    }
    collector.cancel()
    await broker.cancelAll()
    return nil
}

@Suite("Acceptance: 質問の isSecret（伏せ字入力）対応（task-5）")
struct AcceptanceUserQuestionSecretTests {
    @Test("codex の isSecret=true が ChatUserQuestion まで運ばれる")
    func secretIsCarriedThroughBridge() async throws {
        let question = try #require(await bridgedQuestion(isSecret: true))
        #expect(question.isSecret == true)
    }

    @Test("isSecret が false / 省略のときは false になる")
    func secretDefaultsToFalse() async throws {
        let explicitFalse = try #require(await bridgedQuestion(isSecret: false))
        #expect(explicitFalse.isSecret == false)

        let omitted = try #require(await bridgedQuestion(isSecret: nil))
        #expect(omitted.isSecret == false)
    }

    @Test("ChatUserQuestion の既定は isSecret == false（Claude 経路は挙動不変）")
    func defaultInitKeepsExistingBehaviour() {
        let question = ChatUserQuestion(
            question: "どの方式にしますか？",
            header: "方式",
            options: [ChatUserQuestionOption(label: "A案")],
            multiSelect: false
        )
        #expect(question.isSecret == false)
    }

    @Test("isSecret が無い既存 JSON も従来どおりデコードできる（永続データ互換）")
    func decodesLegacyJSONWithoutSecretField() throws {
        let json = """
        {"question":"どの方式にしますか？","header":"方式","options":[{"label":"A案"}],"multiSelect":false}
        """
        let decoded = try JSONDecoder().decode(ChatUserQuestion.self, from: Data(json.utf8))
        #expect(decoded.isSecret == false)
        #expect(decoded.question == "どの方式にしますか？")
    }

    @Test("質問カードが isSecret のとき伏せ字入力を描画する")
    func cardRendersSecureField() throws {
        // 到達性: 型に値が乗っても View が分岐していなければユーザーには平文のまま見える。
        let card = try source(of: "UserQuestionCell.swift")
        #expect(card.contains("SecureField"), "isSecret の自由入力欄が SecureField になっていない")
        #expect(card.contains("isSecret"), "UserQuestionCell が isSecret で分岐していない")
    }

    @Test("回答済みカードは isSecret の回答を平文表示しない")
    func answeredCardMasksSecret() throws {
        // 回答済み表示（answeredLabels）が isSecret を考慮していること。
        let card = try source(of: "UserQuestionCell.swift")
        let hasMaskBranch = card.contains("isSecret") &&
            (card.contains("●") || card.contains("•") || card.contains("maskedAnswer") || card.contains("String(repeating:"))
        #expect(hasMaskBranch, "回答済みカードで isSecret の回答をマスクしていない")
    }
}
