import Foundation
import Testing
@testable import SessionFeature

/// UserQuestionCell.swift から指定シグネチャの関数本体だけを切り出す。
/// 次の private func / @ViewBuilder までを本体とみなす、既存流儀の白箱検査。
private func functionBody(of signature: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SessionFeatureTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // SessionFeature(package root)
        .appendingPathComponent("Sources/SessionFeature/UserQuestionCell.swift")
    let source = try String(contentsOf: url, encoding: .utf8)
    let start = try #require(source.range(of: signature))
    let rest = source[start.upperBound...]
    let end = rest.range(of: "\n    private func") ?? rest.range(of: "\n    @ViewBuilder")
    return String(rest[..<(end?.lowerBound ?? rest.endIndex)])
}

@Suite("Whitebox: UserQuestionCell の伏せ字回答表示（task-5）")
struct UserQuestionSecretWhiteboxTests {
    @Test("回答済み表示用のラベルは秘密の回答だけを固定長のマスクへ置き換える")
    func answeredDisplayLabelsMaskSecretsWithoutChangingPlainTextAnswers() {
        #expect(
            UserQuestionAnswerDisplay.labels(
                for: ["api-key-123"],
                isSecret: true
            ) == [String(repeating: "●", count: 8)]
        )
        #expect(
            UserQuestionAnswerDisplay.labels(
                for: ["A案"],
                isSecret: false
            ) == ["A案"]
        )
    }

    @Test("回答済みカードの表示は必ずマスクヘルパーを通る（呼び出し側に束縛）")
    func answeredLabelsGoThroughMaskHelper() throws {
        let body = try functionBody(of: "private func answeredLabels(")
        #expect(
            body.contains("UserQuestionAnswerDisplay.labels("),
            "answeredLabels がマスクヘルパーを呼んでいない"
        )
        #expect(
            body.contains("label: displayLabels["),
            "optionLabel へ渡すラベルがマスク済みの配列由来でない（生の回答が渡っている疑い）"
        )
        #expect(
            !body.contains("label: answer,") && !body.contains("label: selected["),
            "生の回答が optionLabel へ直接渡っている"
        )
    }

    @Test("回答済み表示のマスク判定は質問の isSecret を使う")
    func answeredLabelsUseQuestionSecretFlag() throws {
        let body = try functionBody(of: "private func answeredLabels(")
        #expect(
            body.contains("isSecret: question.isSecret"),
            "answeredLabels が質問の isSecret をマスクヘルパーへ渡していない"
        )
    }

    @Test("自由入力欄の伏せ字分岐は質問の isSecret に束縛される")
    func freeTextInputUsesQuestionSecretFlag() throws {
        let body = try functionBody(of: "private func freeTextInput(")
        #expect(
            body.contains("if question.isSecret {"),
            "自由入力欄が質問の isSecret で分岐していない"
        )
        #expect(
            body.contains("SecureField("),
            "isSecret 側の自由入力欄が SecureField ではない"
        )
        #expect(
            body.contains("TextField("),
            "非 isSecret 側の自由入力欄が TextField ではない"
        )
    }
}
