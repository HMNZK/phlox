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
    static func lines(usedTokens: Int, windowTokens: Int) -> [String] {
        let percent: Int
        if windowTokens > 0 {
            percent = Int((Double(usedTokens) / Double(windowTokens) * 100).rounded())
        } else {
            percent = 0
        }
        return [
            "Context window:",
            "\(percent)% used (\(100 - percent)% left)",
            "\(tokenText(usedTokens)) / \(tokenText(windowTokens)) tokens used",
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
        case .regular: 2
        case .compact: 2
        }
    }

    /// `.regular` は幅制約なし（既存挙動）。`.compact` はグリッド列幅向けに絞る。
    static func branchNameMaxWidth(for layout: ComposerIndicatorLayout) -> CGFloat? {
        switch layout {
        case .regular: nil
        case .compact: 100
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

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            if let fraction = ComposerContextGauge.fraction(for: usage) {
                contextDonut(fraction: fraction)
            }
            branchLabel
        }
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
        let strokeColor = ComposerContextGauge.isWarningLevel(fraction: fraction)
            ? DSColor.statusAwaitingApproval
            : DSColor.chatAccent
        let diameter = ComposerIndicatorMetrics.donutDiameter(for: layout)
        let strokeWidth = ComposerIndicatorMetrics.donutStrokeWidth(for: layout)

        if let popoverLines = contextPopoverLines {
            HoverableComposerControl { isHovering in
                ZStack {
                    Circle()
                        .stroke(DSColor.chatTextSecondary.opacity(0.28), lineWidth: strokeWidth)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: diameter, height: diameter)
                .overlay(alignment: .top) {
                    if isHovering {
                        ComposerContextPopover(lines: popoverLines)
                            .fixedSize()
                            .offset(y: -58)
                            .allowsHitTesting(false)
                            .zIndex(10)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

    private var contextPopoverLines: [String]? {
        guard let usage,
              let used = ComposerContextGauge.resolvedUsedTokens(from: usage),
              let window = usage.contextWindowTokens,
              window > 0
        else { return nil }
        return ComposerContextPopoverText.lines(usedTokens: used, windowTokens: window)
    }
}

private struct ComposerContextPopover: View {
    let lines: [String]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.chatTextPrimary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .background(DSColor.chatElevated, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .stroke(DSColor.border)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 6)
    }
}

private struct ComposerBranchControl: View {
    let workspacePath: String
    var layout: ComposerIndicatorLayout = .regular

    @State private var currentBranch: String?
    @State private var picker = ComposerBranchPickerModel()
    @State private var isCheckingOut = false
    @State private var checkoutError: String?

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
        HoverableComposerControl(isEnabled: !isCheckingOut) { _ in
            Button {
                openPicker()
            } label: {
                ComposerBranchLabelContent(
                    currentBranch: currentBranch,
                    layout: layout,
                    isCheckingOut: isCheckingOut
                )
            }
            .buttonStyle(.plain)
            .disabled(isCheckingOut)
            .popover(isPresented: pickerIsPresented, arrowEdge: .top) {
                branchPicker
            }
            .alert("Branch checkout failed", isPresented: checkoutErrorIsPresented) {
                Button("OK", role: .cancel) {
                    checkoutError = nil
                }
            } message: {
                Text(checkoutError ?? "")
            }
        }
    }

    private var branchPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            if picker.branches.isEmpty {
                Text("No local branches")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.chatTextSecondary)
                    .padding(.horizontal, DSSpacing.s)
                    .padding(.vertical, DSSpacing.s)
            } else {
                ForEach(picker.branches, id: \.self) { branch in
                    Button {
                        checkout(branch)
                    } label: {
                        SettingsMenuRow(
                            title: branch,
                            isSelected: branch == currentBranch
                        )
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.chatTextPrimary)
                        .padding(.horizontal, DSSpacing.s)
                        .padding(.vertical, DSSpacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingOut || branch == currentBranch)
                }
            }
        }
        .frame(minWidth: 190, alignment: .leading)
        .padding(.vertical, DSSpacing.xs)
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
        isCheckingOut = true
        Task {
            do {
                let path = workspacePath
                try await Task.detached(priority: .userInitiated) {
                    try GitBranchSwitcher.checkout(branch: branch, at: path)
                }.value
                currentBranch = branch
            } catch {
                checkoutError = shortErrorMessage(from: error)
                refreshCurrentBranch()
            }
            isCheckingOut = false
        }
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
        HoverableComposerControl(isEnabled: !isCheckingOut) { _ in
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
}

private struct ComposerBranchLabelContent: View {
    let currentBranch: String
    var layout: ComposerIndicatorLayout
    var isCheckingOut: Bool

    var body: some View {
        let truncation = ComposerIndicatorMetrics.branchTruncationMode(for: layout)
        let label = HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .medium))
            Text(currentBranch)
                .font(DSFont.caption)
                .lineLimit(1)
                .truncationMode(truncation)
            if isCheckingOut {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
            }
        }
        .foregroundStyle(DSColor.chatTextSecondary)
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))

        if let maxWidth = ComposerIndicatorMetrics.branchNameMaxWidth(for: layout) {
            label.frame(maxWidth: maxWidth)
        } else {
            label
        }
    }
}
