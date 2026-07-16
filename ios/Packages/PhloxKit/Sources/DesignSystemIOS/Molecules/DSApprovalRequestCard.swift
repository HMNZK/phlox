import SwiftUI
import PhloxCore

/// 承認リクエストカード（カンプ③）。黄ボーダー・ラベル・プロンプト（ファイル名はモノピンク強調）。
public struct DSApprovalRequestCard: View {
    /// セクションラベル（カンプ固定文言）。
    static let labelText = "承認リクエスト"
    /// 黄ボーダー不透明度（`rgba(251,191,36,.3)`）。
    static let borderOpacity = 0.3

    /// プロンプトの 1 断片。`isEmphasized` のときモノスペース＋ピンクで描画する。
    struct PromptSegment: Equatable, Sendable {
        let text: String
        let isEmphasized: Bool
    }

    let prompt: String
    let emphasizedFileName: String

    public init(prompt: String, emphasizedFileName: String) {
        self.prompt = prompt
        self.emphasizedFileName = emphasizedFileName
    }

    public init(approval: Approval) {
        self.prompt = approval.prompt
        self.emphasizedFileName = Self.extractEmphasizedFileName(from: approval.prompt) ?? ""
    }

    /// 先頭の `name.ext` 形式トークンを強調ファイル名として抽出する（テスト可能な決定点）。
    static func extractEmphasizedFileName(from prompt: String) -> String? {
        guard let first = prompt.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first
        else { return nil }
        let token = String(first)
        guard token.contains("."), !token.hasSuffix(".") else { return nil }
        return token
    }

    /// プロンプトを通常文と強調ファイル名に分割する（テスト可能な決定点）。
    static func promptSegments(prompt: String, emphasizedFileName: String) -> [PromptSegment] {
        guard !emphasizedFileName.isEmpty, let range = prompt.range(of: emphasizedFileName) else {
            return [PromptSegment(text: prompt, isEmphasized: false)]
        }
        var segments: [PromptSegment] = []
        if range.lowerBound > prompt.startIndex {
            segments.append(PromptSegment(
                text: String(prompt[prompt.startIndex..<range.lowerBound]),
                isEmphasized: false
            ))
        }
        segments.append(PromptSegment(text: emphasizedFileName, isEmphasized: true))
        if range.upperBound < prompt.endIndex {
            segments.append(PromptSegment(
                text: String(prompt[range.upperBound...]),
                isEmphasized: false
            ))
        }
        return segments
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(Self.labelText)
                .font(DSFont.footnote.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(DSColor.statusAwaitingApproval)

            promptText
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.campSurfaceEmphasis, in: cardShape)
        .overlay(cardShape.strokeBorder(DSColor.statusAwaitingApproval.opacity(Self.borderOpacity), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Self.labelText)、\(prompt)"))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
    }

    private var promptText: Text {
        Self.promptSegments(prompt: prompt, emphasizedFileName: emphasizedFileName)
            .reduce(Text("")) { partial, segment in
                let styled: Text
                if segment.isEmphasized {
                    styled = Text(segment.text)
                        .font(DSFont.campMono)
                        .foregroundStyle(DSColor.campAttention)
                } else {
                    styled = Text(segment.text)
                }
                return partial + styled
            }
    }
}

#if DEBUG
#Preview("DSApprovalRequestCard") {
    VStack(spacing: DSSpacing.m) {
        DSApprovalRequestCard(
            prompt: "ControlServer.swift を削除し、proxy 経由の実装に置き換えます。実行を承認しますか？",
            emphasizedFileName: "ControlServer.swift"
        )
        DSApprovalRequestCard(
            approval: Approval(
                id: "a1",
                sessionID: "s1",
                kind: .claudeCode,
                prompt: "削除しますか？"
            )
        )
    }
    .padding(DSSpacing.l)
}
#endif
