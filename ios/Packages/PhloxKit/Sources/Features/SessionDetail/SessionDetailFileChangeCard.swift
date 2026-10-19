import Foundation
import SwiftUI
import ChatRenderKit
import DesignSystemIOS
import PhloxCore

/// 1 行分の diff 表示データ。`body` は共有分類結果からマーカーを除いた本文。
struct SessionDetailDiffCodeLine: Identifiable {
    let id: Int
    let text: String
    let kind: ChatDiffLineKind
    let displayLineNumber: Int?

    init(id: Int, classified: ChatDiffLine) {
        self.id = id
        self.text = classified.text
        self.kind = classified.kind
        self.displayLineNumber = classified.displayLineNumber
    }

    var body: String {
        switch kind {
        case .addition, .deletion:
            String(text.dropFirst())
        case .context:
            text.first == " " ? String(text.dropFirst()) : text
        case .fileHeader, .hunk:
            text
        }
    }

    var marker: String {
        switch kind {
        case .addition: "+"
        case .deletion: "-"
        case .context: text.first == " " ? " " : ""
        case .fileHeader, .hunk: ""
        }
    }

}

/// ファイル変更カードが必要とする表示用の値を、共有分類結果から組み立てる純粋なデータ。
struct SessionDetailDiffCodeViewData {
    let lines: [SessionDetailDiffCodeLine]
    let hasLineNumbers: Bool
    let lineNumberWidth: Int
    let title: String
    let path: String
    let additions: Int
    let deletions: Int
    var countBadges: [SessionDetailDiffCountBadge] {
        [
            additions > 0 ? SessionDetailDiffCountBadge(kind: .addition, count: additions) : nil,
            deletions > 0 ? SessionDetailDiffCountBadge(kind: .deletion, count: deletions) : nil,
        ].compactMap { $0 }
    }
    /// 表示用に除去した行を含む、入力 diff の原文。
    let copyText: String
    let isExpandedByDefault: Bool

    init(change: ChatFileChange) {
        let patch = ChatFilePatch(path: change.path, diff: change.diff, kind: change.kind)
        let counts = ChatFileChangePresentation.counts(for: [patch])
        lines = ChatDiffClassifier.classify(change.diff).enumerated().compactMap { id, classified in
            guard classified.isDisplayable, classified.kind != .hunk else { return nil }
            return SessionDetailDiffCodeLine(id: id, classified: classified)
        }
        let confirmedNumbers = lines.compactMap(\.displayLineNumber)
        lineNumberWidth = confirmedNumbers.map { String($0).count }.max() ?? 0
        hasLineNumbers = !confirmedNumbers.isEmpty
        let verb = ChatFileChangePresentation.verb(for: change.kind)
        title = switch verb {
        case "作成済み": "作成"
        case "削除済み": "削除"
        case "編集済み": "編集"
        default: "変更"
        }
        path = change.path
        additions = counts.additions
        deletions = counts.deletions
        copyText = change.diff
        isExpandedByDefault = false
    }
}

struct SessionDetailDiffCountBadge: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case addition
        case deletion
    }

    let kind: Kind
    let count: Int

    var id: String { kind.rawValue }
    var text: String { "\(kind == .addition ? "+" : "−")\(count)" }
}

struct SessionDetailFileChangeCard: View {
    let data: SessionDetailDiffCodeViewData
    let isExpanded: Bool
    let onToggle: () -> Void
    @ScaledMetric(relativeTo: .caption) private var monoAdvance: CGFloat = 8

    init(
        change: ChatFileChange,
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) {
        data = SessionDetailDiffCodeViewData(change: change)
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    var body: some View {
        DSChatCodeCard(showsDivider: isExpanded) {
            SessionDetailTranscriptCardHeader(
                label: data.title,
                summary: data.path,
                badges: data.countBadges.map { badge in
                    SessionDetailTranscriptBadge(
                        id: badge.id,
                        text: badge.text,
                        color: badge.kind == .addition ? DSColor.diffAdded : DSColor.diffRemoved,
                        monospaced: true,
                        weight: .semibold
                    )
                },
                isExpanded: isExpanded,
                allowsDisclosure: true,
                onToggle: onToggle
            )
        } content: {
            DSDisclosureContent(isExpanded: isExpanded) {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: .zero) {
                        ForEach(data.lines) { line in
                            diffLineView(line)
                        }
                    }
                }
                .padding(.top, DSSpacing.s)
                .padding(.bottom, DSSpacing.s)
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        ChatMessageCopyAction.copyToPasteboard(data.copyText)
                    } label: {
                        Text("セクションをコピー")
                            .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressFeedbackStyle())
                    .font(DSFont.iosCaption2)
                    .foregroundStyle(IOSColor.text.secondary)
                    .accessibilityIdentifier("SessionDetailFileChangeCard.copySection")
                }
                .padding(.horizontal, DSSpacing.m)
                .padding(.bottom, DSSpacing.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("SessionDetailFileChangeCard")
    }

    private func diffLineView(_ line: SessionDetailDiffCodeLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s) {
            if data.hasLineNumbers {
                Text(line.displayLineNumber.map(String.init) ?? "")
                    .font(DSFont.campMonoCaption)
                    .foregroundStyle(IOSColor.text.tertiary)
                    .frame(width: CGFloat(data.lineNumberWidth) * monoAdvance, alignment: .trailing)
            }

            Text(line.marker)
                .font(DSFont.campMonoCaption)
                .foregroundStyle(foreground(for: line.kind))
                .frame(width: monoAdvance, alignment: .leading)

            Text(line.body)
                .font(DSFont.campMonoCaption)
                .foregroundStyle(IOSColor.text.primary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, DSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(for: line.kind))
    }

    private func foreground(for kind: ChatDiffLineKind) -> Color {
        switch kind {
        case .addition: DSColor.diffAdded
        case .deletion: DSColor.diffRemoved
        case .context: DSColor.chatTextPrimary
        case .fileHeader, .hunk: DSColor.chatTextSecondary
        }
    }

    private func background(for kind: ChatDiffLineKind) -> Color {
        switch kind {
        case .addition: DSColor.diffAdded.opacity(0.12)
        case .deletion: DSColor.diffRemoved.opacity(0.12)
        case .context, .fileHeader, .hunk: .clear
        }
    }
}
