import SwiftUI
import StructuredChatKit

/// AskUserQuestion の質問カード（task-0 骨組み）。
/// task-2 が選択肢ボタン・multiSelect・自由入力・回答送信・answered/expired 表示へ差し替える。
struct UserQuestionCell: View {
    let itemId: String
    let questions: [ChatUserQuestion]
    let answers: [String: [String]]?
    let state: ChatUserQuestionState
    let timestamp: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(questions, id: \.question) { question in
                Text(question.header)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(question.question)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
