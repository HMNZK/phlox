import Foundation
import SwiftUI
import ChatRenderKit
import DesignSystemIOS
import PhloxCore

/// 1 行分の diff 表示データ。`text` は元の diff 行、`body` はマーカーを除いた本文。
struct SessionDetailDiffCodeLine: Identifiable {
    let id: Int
    let fileIndex: Int
    let path: String
    let text: String
    let kind: ChatDiffLineKind
    let displayLineNumber: Int?
    let highlightedBody: AttributedString

    var body: String {
        switch kind {
        case .addition, .deletion:
            return String(text.dropFirst())
        case .context:
            return text.first == " " ? String(text.dropFirst()) : text
        case .fileHeader, .hunk:
            return text
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
    let additions: Int
    let deletions: Int
    let fullPaths: [String]
    /// 表示用に除去した行を含む、入力 diff の原文。
    let copyText: String
    let isExpandedByDefault: Bool

    init(changes: [ChatFileChange]) {
        let patches = changes.map {
            ChatFilePatch(path: $0.path, diff: $0.diff, kind: $0.kind)
        }
        let counts = ChatFileChangePresentation.counts(for: patches)

        var nextID = 0
        lines = changes.enumerated().flatMap { fileIndex, change in
            ChatDiffClassifier.classify(change.diff).compactMap { classified in
                guard classified.isDisplayable, classified.kind != .hunk else { return nil }

                let body = Self.body(of: classified)
                let line = SessionDetailDiffCodeLine(
                    id: nextID,
                    fileIndex: fileIndex,
                    path: change.path,
                    text: classified.text,
                    kind: classified.kind,
                    displayLineNumber: classified.displayLineNumber,
                    highlightedBody: CodeHighlighter.diff(body, path: change.path)
                )
                nextID += 1
                return line
            }
        }

        let confirmedNumbers = lines.compactMap(\.displayLineNumber)
        lineNumberWidth = confirmedNumbers.map { String($0).count }.max() ?? 0
        hasLineNumbers = !confirmedNumbers.isEmpty
        title = ChatFileChangePresentation.title(for: patches)
        additions = counts.additions
        deletions = counts.deletions
        fullPaths = changes.map(\.path)
        copyText = changes.map(\.diff).joined(separator: "\n\n")
        isExpandedByDefault = false
    }

    func lines(forFileAt fileIndex: Int) -> [SessionDetailDiffCodeLine] {
        lines.filter { $0.fileIndex == fileIndex }
    }

    private static func body(of line: ChatDiffLine) -> String {
        switch line.kind {
        case .addition, .deletion:
            return String(line.text.dropFirst())
        case .context:
            return line.text.first == " " ? String(line.text.dropFirst()) : line.text
        case .fileHeader, .hunk:
            return line.text
        }
    }
}

struct SessionDetailFileChangeCard: View {
    let data: SessionDetailDiffCodeViewData
    let isExpanded: Bool
    let onToggle: () -> Void

    init(
        changes: [ChatFileChange],
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.init(
            data: SessionDetailDiffCodeViewData(changes: changes),
            isExpanded: isExpanded,
            onToggle: onToggle
        )
    }

    init(
        data: SessionDetailDiffCodeViewData,
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.data = data
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    var body: some View {
        DSChatCodeCard {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                    Text(data.title)
                        .font(DSFont.captionStrong)
                        .foregroundStyle(DSColor.chatTextSecondary)
                    Text("+\(data.additions)")
                        .font(DSFont.captionStrong)
                        .foregroundStyle(DSColor.diffAdded)
                    Text("-\(data.deletions)")
                        .font(DSFont.captionStrong)
                        .foregroundStyle(DSColor.diffRemoved)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(DSFont.footnote.weight(.semibold))
                        .foregroundStyle(DSColor.chatTextSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: DSTouch.minSize, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } content: {
            if isExpanded {
                VStack(alignment: .leading, spacing: DSSpacing.m) {
                    ForEach(Array(data.fullPaths.enumerated()), id: \.offset) { file in
                        VStack(alignment: .leading, spacing: .zero) {
                            Text(file.element)
                                .font(DSFont.campMonoCaption)
                                .foregroundStyle(DSColor.chatTextSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .padding(.horizontal, DSSpacing.m)
                                .padding(.bottom, DSSpacing.xs)

                            VStack(alignment: .leading, spacing: .zero) {
                                ForEach(data.lines(forFileAt: file.offset)) { line in
                                    diffLineView(line)
                                }
                            }
                        }
                    }
                }
                .padding(.top, DSSpacing.s)
                .padding(.bottom, DSSpacing.m)
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
                    .foregroundStyle(foreground(for: line.kind))
                    .frame(width: CGFloat(data.lineNumberWidth) * 8, alignment: .trailing)
            }

            Text(line.marker)
                .font(DSFont.campMonoCaption)
                .foregroundStyle(foreground(for: line.kind))
                .frame(width: 8, alignment: .leading)

            Text(line.highlightedBody)
                .font(DSFont.campMonoCaption)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, DSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(for: line.kind))
        .textSelection(.enabled)
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
