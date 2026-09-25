import SwiftUI
import DesignSystem
import StructuredChatKit

enum ComposerContextGauge {
    static let warningFractionThreshold = 0.8

    static func fraction(for usage: TurnUsage?) -> Double? {
        guard let usage else { return nil }
        guard let used = resolvedUsedTokens(from: usage) else { return nil }
        guard let window = usage.contextWindowTokens, window > 0 else { return nil }
        return min(max(Double(used) / Double(window), 0), 1)
    }

    static func resolvedUsedTokens(from usage: TurnUsage) -> Int? {
        if let explicit = usage.contextUsedTokens {
            return explicit
        }
        var sum = 0
        var hasAny = false
        if let input = usage.inputTokens {
            sum += input
            hasAny = true
        }
        if let cacheRead = usage.cacheReadTokens {
            sum += cacheRead
            hasAny = true
        }
        if let cacheCreation = usage.cacheCreationTokens {
            sum += cacheCreation
            hasAny = true
        }
        return hasAny ? sum : nil
    }

    static func helpText(for usage: TurnUsage?) -> String? {
        guard let usage,
              let used = resolvedUsedTokens(from: usage),
              let window = usage.contextWindowTokens,
              window > 0,
              let fraction = fraction(for: usage)
        else { return nil }
        let percent = Int((fraction * 100).rounded())
        return "使用 \(percent)% (\(used)/\(window))"
    }

    static func isWarningLevel(fraction: Double) -> Bool {
        fraction >= warningFractionThreshold
    }
}

enum ComposerContextPopoverText {
    static func lines(usedTokens: Int, windowTokens: Int, languageCode: String = "en") -> [String] {
        let percent: Int
        if windowTokens > 0 {
            percent = Int((Double(usedTokens) / Double(windowTokens) * 100).rounded())
        } else {
            percent = 0
        }
        return [
            UIWording.text(.contextWindowHeading, languageCode: languageCode),
            UIWording.contextUsagePercent(usedPercent: percent, remainingPercent: 100 - percent, languageCode: languageCode),
            UIWording.contextTokenUsage(usedText: tokenText(usedTokens), windowText: tokenText(windowTokens), languageCode: languageCode),
        ]
    }

    static func tokenText(_ tokens: Int) -> String {
        guard tokens >= 1_000 else { return "\(tokens)" }
        return "\(Int((Double(tokens) / 1_000).rounded()))k"
    }
}

/// composer フッターのコンテキスト・ブランチ表示のレイアウト（task-3 契約面）。
/// `.regular` はシングルビュー（既存挙動そのまま）、`.compact` はグリッドビューの狭い列幅向け。
enum ComposerIndicatorLayout: Equatable {
    case regular
    case compact
}

enum ComposerIndicatorMetrics {
    static func donutDiameter(for layout: ComposerIndicatorLayout) -> CGFloat {
        switch layout {
        case .regular: 14
        case .compact: 12
        }
    }

    static func donutStrokeWidth(for layout: ComposerIndicatorLayout) -> CGFloat {
        switch layout {
        case .regular: 2.2
        case .compact: 2.2
        }
    }

    /// どちらの layout も固定の上限クランプは設けない（省略は親 HStack の実領域不足時のみ）。
    static func branchNameMaxWidth(for layout: ComposerIndicatorLayout) -> CGFloat? {
        switch layout {
        case .regular, .compact: nil
        }
    }

    static func branchTruncationMode(for layout: ComposerIndicatorLayout) -> Text.TruncationMode {
        .middle
    }
}

struct ComposerContextIndicator: View {
    let usage: TurnUsage?
    let workspacePath: String
    var layout: ComposerIndicatorLayout = .regular
    var branchNameOverride: String?
    var branchIsCheckingOutOverride = false
    /// 600pt 未満（compact）ではブランチを隠す（05「幅による下の列の切り替え」）。
    var showsBranch = true
    /// 80% を超えたとき /compact を案内するか（/compact を持つエージェントだけ）。
    var suggestsCompact = false
    @Environment(\.locale) private var locale
    @State private var isHoveringContext = false

    /// PhloxReply.dc.html の下段の右: ブランチ（等幅 11）→ コンテキストの円＋%（11.5・fg2・等幅数字）。
    var body: some View {
        HStack(spacing: 6) {
            if showsBranch {
                branchLabel
                    // フッター幅不足時は送信・停止ボタンより先に圧縮させる（不変条件 i）。
                    .layoutPriority(-1)
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .trailing)
            }
            if let fraction = ComposerContextGauge.fraction(for: usage) {
                HStack(spacing: 5) {
                    contextDonut(fraction: fraction)
                    Text(verbatim: "\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize()
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var branchLabel: some View {
        let expanded = (workspacePath as NSString).expandingTildeInPath
        if let branchNameOverride, !branchNameOverride.isEmpty {
            ComposerStaticBranchControl(
                currentBranch: branchNameOverride,
                layout: layout,
                isCheckingOut: branchIsCheckingOutOverride
            )
        } else if !expanded.isEmpty {
            ComposerBranchControl(workspacePath: expanded, layout: layout)
        }
    }

    @ViewBuilder
    private func contextDonut(fraction: Double) -> some View {
        // 通常は fg2、80% 以上は `--apv`。下地は `--segBg`、太さ 2.2・端は角。
        let strokeColor = ComposerContextGauge.isWarningLevel(fraction: fraction)
            ? DSColor.attentionMark(.approval)
            : DSColor.textSecondary
        let diameter = ComposerIndicatorMetrics.donutDiameter(for: layout)
        let strokeWidth = ComposerIndicatorMetrics.donutStrokeWidth(for: layout)

        if let popoverLines = contextPopoverLines {
            let isHovering = isHoveringContext
                ZStack {
                    Circle()
                        .stroke(DSColor.segmentTrack, lineWidth: strokeWidth)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: diameter, height: diameter)
                .overlay(alignment: .topTrailing) {
                    if isHovering {
                        ComposerContextPopover(
                            summary: popoverLines,
                            warning: suggestsCompact && ComposerContextGauge.isWarningLevel(fraction: fraction)
                                ? AppLocalizedString.string("80% を超えました。/compact で会話を圧縮できます。", locale: locale)
                                : nil
                        )
                            .fixedSize()
                            .placedAbove(gap: 8)
                            .allowsHitTesting(false)
                            .zIndex(10)
                    }
                }
                .onHover { isHoveringContext = $0 }
                .reportsComposerPopup(isHovering)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: popoverLines.title))
                .accessibilityValue(Text(verbatim: popoverLines.tokens))
        } else {
            EmptyView()
        }
    }

    /// 吹き出しの 2 行（「コンテキスト 84%」「168k / 200k トークン」）。
    private var contextPopoverLines: (title: String, tokens: String)? {
        guard let usage,
              let used = ComposerContextGauge.resolvedUsedTokens(from: usage),
              let window = usage.contextWindowTokens,
              window > 0
        else { return nil }
        let percent = Int((Double(used) / Double(window) * 100).rounded())
        return (
            String(format: AppLocalizedString.string("コンテキスト %lld%%", locale: locale), percent),
            String(
                format: AppLocalizedString.string("%@ / %@ トークン", locale: locale),
                ComposerContextPopoverText.tokenText(used),
                ComposerContextPopoverText.tokenText(window)
            )
        )
    }
}

/// PhloxReply.dc.html の O8: 右寄せ・幅 240・`--popover`・角丸 9・影。
private struct ComposerContextPopover: View {
    let summary: (title: String, tokens: String)
    var warning: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: summary.title)
                .fontWeight(.semibold)
                .foregroundStyle(DSColor.textPrimary)
            Text(verbatim: summary.tokens)
                .monospacedDigit()
                .foregroundStyle(DSColor.textSecondary)
            if let warning {
                Text(verbatim: warning)
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(DSColor.attentionInk(.approval))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 240, alignment: .leading)
        .background(DSColor.popoverBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(DSColor.popoverEdge, lineWidth: 0.5)
        )
        .dsShadow(.popover)
    }
}

private struct ComposerBranchControl: View {
    let workspacePath: String
    var layout: ComposerIndicatorLayout = .regular
    @Environment(\.locale) private var locale

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    @State private var currentBranch: String?
    @State private var picker = ComposerBranchPickerModel()
    @State private var isCheckingOut = false
    @State private var checkoutError: String?
    @State private var failedBranch: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            Group {
                if let currentBranch {
                    branchButton(currentBranch: currentBranch)
                }
            }
            .task(id: workspacePath) {
                guard picker.allowsExternalRefresh else { return }
                refreshCurrentBranch()
            }
            .task(id: timeline.date) {
                guard picker.allowsExternalRefresh else { return }
                refreshCurrentBranch()
            }
        }
    }

    private func branchButton(currentBranch: String) -> some View {
        Button {
            if picker.isPresented { pickerIsPresented.wrappedValue = false } else { openPicker() }
        } label: {
            ComposerBranchLabelContent(
                currentBranch: currentBranch,
                layout: layout,
                isCheckingOut: isCheckingOut,
                isOpen: picker.isPresented
            )
        }
        .buttonStyle(.plain)
        .disabled(isCheckingOut)
        .accessibilityLabel(Text(verbatim: AppLocalizedString.string("ブランチ", locale: locale) + " " + currentBranch))
        .composerPopup(isPresented: pickerIsPresented, alignment: .trailing) {
            ComposerPopupSurface(width: 300, cornerRadius: 10, padding: 6) {
                branchPicker
            }
        }
        // 09 C 型: 起きたことを言い切り、git の出力はそのまま等幅で。
        .dsDialog(isPresented: checkoutErrorIsPresented) {
            DSDialog(
                .notice,
                title: UIWording.text(.branchCheckoutFailed, languageCode: languageCode),
                buttons: [DSDialogButton("OK", role: .primary) { checkoutError = nil }],
                onCancel: { checkoutError = nil }
            ) {
                DSDialogLog(checkoutError ?? "")
            }
        }
    }

    /// PhloxReply.dc.html の O7: 見出し「ブランチを切り替え · ~/dev/phlox」、等幅 12 の行（高さ 26）。
    /// 切り替えに失敗したら、一覧の下に errTint の面で理由を出す（開いたまま）。
    private var branchPicker: some View {
        let header = AppLocalizedString.string("ブランチを切り替え", locale: locale) + " · " + (workspacePath as NSString).abbreviatingWithTildeInPath
        return VStack(alignment: .leading, spacing: 0) {
            if picker.branches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: header)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DSColor.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                    Text(UIWording.text(.noLocalBranches, languageCode: languageCode))
                        .font(.system(size: 12))
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            } else {
                ComposerMenuList(
                    header: header,
                    sections: [ComposerMenuSection(id: "branches", rows: picker.branches.map { branch in
                        ComposerMenuRow(
                            id: branch,
                            title: branch,
                            isSelected: branch == currentBranch,
                            isEnabled: !isCheckingOut,
                            action: { checkout(branch) }
                        )
                    })],
                    rowHeight: 26,
                    monospacedRows: true,
                    onClose: {}
                )
            }
            if let reason = picker.checkoutErrorMessage, let branch = failedBranch {
                Text(verbatim: String(format: AppLocalizedString.string("%@ に切り替えられません: %@", locale: locale), branch, Self.firstLine(reason)))
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .foregroundStyle(DSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 9)
                    .frame(width: 288, alignment: .leading)
                    .background(DSColor.attentionTint(.error), in: RoundedRectangle(cornerRadius: 6))
                    .padding(EdgeInsets(top: 5, leading: 0, bottom: 2, trailing: 0))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    private var checkoutErrorIsPresented: Binding<Bool> {
        Binding(
            get: { checkoutError != nil },
            set: { isPresented in
                if !isPresented {
                    checkoutError = nil
                }
            }
        )
    }

    private var pickerIsPresented: Binding<Bool> {
        Binding(
            get: { picker.isPresented },
            set: { isPresented in
                if !isPresented {
                    picker.dismiss()
                    refreshCurrentBranch()
                }
            }
        )
    }

    private func refreshCurrentBranch() {
        currentBranch = GitBranchReader.currentBranch(at: workspacePath)
    }

    private func openPicker() {
        guard picker.phase == .idle else { return }
        picker.beginOpen()
        Task {
            do {
                let path = workspacePath
                let branches = try await Task.detached(priority: .userInitiated) {
                    try GitBranchSwitcher.localBranches(at: path)
                }.value
                picker.finishLoading(.success(branches))
            } catch {
                picker.finishLoading(.failure(error))
                checkoutError = shortErrorMessage(from: error)
            }
        }
    }

    private func checkout(_ branch: String) {
        guard branch != currentBranch, !isCheckingOut else { return }
        picker.select(branch: branch)
        failedBranch = branch
        isCheckingOut = true
        Task {
            do {
                let path = workspacePath
                try await Task.detached(priority: .userInitiated) {
                    try GitBranchSwitcher.checkout(branch: branch, at: path)
                }.value
                currentBranch = branch
                picker.finishCheckout(.success(()), branch: branch)
            } catch {
                picker.finishCheckout(.failure(error), branch: branch)
                if !picker.isPresented { checkoutError = shortErrorMessage(from: error) }
                refreshCurrentBranch()
            }
            isCheckingOut = false
        }
    }

    private static func firstLine(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first else { return trimmed }
        // git の「…would be overwritten by checkout:」は次の行が対象のファイルなので添える。
        if first.hasSuffix(":"), lines.count > 1 { return "\(first) \(lines[1])" }
        return first
    }

    private func shortErrorMessage(from error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return String(describing: error) }
        return message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
    }
}

private struct ComposerStaticBranchControl: View {
    let currentBranch: String
    var layout: ComposerIndicatorLayout
    var isCheckingOut: Bool

    var body: some View {
        Button {} label: {
            ComposerBranchLabelContent(
                currentBranch: currentBranch,
                layout: layout,
                isCheckingOut: isCheckingOut
            )
        }
        .buttonStyle(.plain)
        .disabled(isCheckingOut)
    }
}

// 白箱テスト（ComposerBranchLabelWhiteboxTests）が真のテキスト幅を計測するため internal。
struct ComposerBranchLabelContent: View {
    let currentBranch: String
    var layout: ComposerIndicatorLayout
    var isCheckingOut: Bool
    var isOpen = false

    /// PhloxReply.dc.html の chipBranch: 等幅 11・面なし（開いている間は `--sel`）・高さ 22・左右 8。
    var body: some View {
        HStack(spacing: 2) {
            Text(verbatim: currentBranch)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(ComposerIndicatorMetrics.branchTruncationMode(for: layout))
            if isCheckingOut {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
            }
        }
        .foregroundStyle(DSColor.textPrimary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(isOpen ? DSColor.selectionFill : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if isOpen {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DSColor.textTertiary, lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
