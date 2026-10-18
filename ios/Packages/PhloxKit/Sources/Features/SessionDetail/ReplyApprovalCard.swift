import SwiftUI
import DesignSystemIOS
import PhloxCore
#if canImport(UIKit)
import UIKit
#endif

struct ReplyApprovalCard: View {
    let approval: ReplyApproval?
    let result: ReplyApprovalResult?
    let index: Int
    let count: Int
    let isResponding: Bool
    let isKeyboardVisible: Bool
    let onDecision: (ApprovalDecision) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onShowNext: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isArmed = false
    @State private var armProgress: CGFloat = 0
    @State private var expandedDiffFiles: Set<Int>
    @State private var isDiffVisible: Bool

    init(
        approval: ReplyApproval?,
        result: ReplyApprovalResult?,
        index: Int,
        count: Int,
        isResponding: Bool,
        isKeyboardVisible: Bool,
        onDecision: @escaping (ApprovalDecision) -> Void,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onShowNext: @escaping () -> Void,
        initiallyShowsDiff: Bool = false
    ) {
        self.approval = approval
        self.result = result
        self.index = index
        self.count = count
        self.isResponding = isResponding
        self.isKeyboardVisible = isKeyboardVisible
        self.onDecision = onDecision
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onShowNext = onShowNext
        _expandedDiffFiles = State(initialValue: initiallyShowsDiff ? [0] : [])
        _isDiffVisible = State(initialValue: initiallyShowsDiff)
    }

    var body: some View {
        if let approval {
            if isKeyboardVisible {
                compactCard(approval)
            } else {
                requestCard(approval)
                    .task(id: approval.armKey) { await arm() }
            }
        } else if let result {
            sentCard(result)
        }
    }

    private func requestCard(_ approval: ReplyApproval) -> some View {
        let content = VStack(alignment: .leading, spacing: DSSpacing.m) {
            header(approval)
            Text(approval.subject)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let explanation = approval.explanation {
                Text(explanation)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !approval.diffFiles.isEmpty {
                diffSection(approval)
            }
            decisionButtons(for: approval)
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    content
                }
                .frame(height: 460)
            } else {
                content
            }
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.card)
        .opacity(0.4 + 0.6 * armProgress)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(approval.kindLabel.map { "承認待ち · \($0)" } ?? "承認待ち")
        .accessibilityIdentifier("ReplyApprovalCard")
    }

    private func header(_ approval: ReplyApproval) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    approvalKindLabel(approval)
                    HStack {
                        if count > 1 { pager }
                        Spacer(minLength: DSSpacing.xs)
                        sinceText(approval)
                    }
                }
            } else {
                HStack(spacing: DSSpacing.s) {
                    approvalKindLabel(approval)
                    Spacer(minLength: DSSpacing.xs)
                    if count > 1 { pager }
                    sinceText(approval)
                }
            }
        }
    }

    private func approvalKindLabel(_ approval: ReplyApproval) -> some View {
        HStack(spacing: DSSpacing.s) {
            RoundedRectangle(cornerRadius: 2)
                .fill(IOSColor.status.approval)
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(45))
                .accessibilityHidden(true)
            Text(approval.kindLabel.map { "承認待ち · \($0)" } ?? "承認待ち")
                .font(DSFont.iosCaption.weight(.medium))
                .foregroundStyle(IOSColor.status.approval)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sinceText(_ approval: ReplyApproval) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(ReplyApprovalPolicy.sinceText(startedAt: approval.requestedAt, now: context.date))
                .font(DSFont.iosCaption)
                .foregroundStyle(DSColor.textSecondary)
                .monospacedDigit()
                .fixedSize()
        }
    }

    private var pager: some View {
        HStack(spacing: DSSpacing.xs) {
            Button(action: onPrevious) {
                Text("‹")
                    .font(DSFont.body.weight(.medium))
                    .foregroundStyle(index > 1 ? DSColor.textPrimary : DSColor.textTertiary)
                    .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(index <= 1)
            .accessibilityLabel("前の承認")
            Text("\(index)/\(count)")
                .font(DSFont.iosCaption)
                .foregroundStyle(DSColor.textSecondary)
                .monospacedDigit()
            Button(action: onNext) {
                Text("›")
                    .font(DSFont.body.weight(.medium))
                    .foregroundStyle(index < count ? DSColor.textPrimary : DSColor.textTertiary)
                    .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(index >= count)
            .accessibilityLabel("次の承認")
        }
    }

    private func decisionButtons(for approval: ReplyApproval) -> some View {
        let decisions = approval.buttonDecisions
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: DSSpacing.s) {
                    ForEach(decisions, id: \.rawValue) { decision in
                        decisionButton(decision)
                    }
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: DSSpacing.s
                ) {
                    ForEach(decisions, id: \.rawValue) { decision in
                        decisionButton(decision)
                    }
                }
            }
        }
    }

    private func decisionButton(_ decision: ApprovalDecision) -> some View {
        let isPrimary = decision == .accept
        let title = SessionDetailViewModel.replyApprovalActionLabel(decision)
        return Button {
            guard isArmed, !isResponding else { return }
            onDecision(decision)
        } label: {
            Text(title)
                .font(DSFont.body.weight(isPrimary ? .semibold : .medium))
                .foregroundStyle(buttonForeground(for: decision))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: DSTouch.minSize)
                .padding(.horizontal, DSSpacing.s)
                .background(buttonBackground(for: decision), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isArmed || isResponding)
        .accessibilityIdentifier("ReplyApproval.\(decision.rawValue)")
    }

    private func buttonForeground(for decision: ApprovalDecision) -> Color {
        switch decision {
        case .accept: IOSColor.accentOnFill
        case .decline: IOSColor.status.error
        case .acceptForSession, .cancel: IOSColor.text.primary
        }
    }

    private func buttonBackground(for decision: ApprovalDecision) -> Color {
        switch decision {
        case .accept: IOSColor.accent
        case .acceptForSession, .decline: IOSColor.bg.fill
        case .cancel: .clear
        }
    }

    private func diffSection(_ approval: ReplyApproval) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Button {
                isDiffVisible.toggle()
                expandedDiffFiles = isDiffVisible ? [0] : []
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    Text("差分を見る（\(approval.diffFiles.count) ファイル）")
                        .font(DSFont.iosCaption.weight(.medium))
                    Image(systemName: isDiffVisible ? "chevron.down" : "chevron.right")
                        .font(DSFont.iosCaption.weight(.semibold))
                }
                .foregroundStyle(DSColor.textSecondary)
                .frame(minHeight: DSTouch.minSize, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ReplyApproval.showDiff")
            if isDiffVisible {
                VStack(spacing: DSSpacing.s) {
                    ForEach(Array(approval.diffFiles.enumerated()), id: \.offset) { offset, file in
                        SessionDetailFileChangeCard(
                            change: file,
                            isExpanded: expandedDiffFiles.contains(offset),
                            onToggle: {
                                if expandedDiffFiles.contains(offset) {
                                    expandedDiffFiles.remove(offset)
                                } else {
                                    expandedDiffFiles.insert(offset)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private func compactCard(_ approval: ReplyApproval) -> some View {
        let title = approval.compactTitle
        return HStack(spacing: DSSpacing.s) {
            Text(title)
                .font(DSFont.iosCaption.weight(.medium))
                .foregroundStyle(approval.kindLabel == nil ? DSColor.textPrimary : IOSColor.status.approval)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(approval.compactAccessibilityLabel)
            Spacer(minLength: 0)
            Button("表示", action: hideKeyboard)
                .font(DSFont.iosCaption.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
                .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                .buttonStyle(.plain)
        }
        .padding(.leading, DSSpacing.m)
        .padding(.trailing, DSSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 48)
        .glassSurface(.card)
        .accessibilityIdentifier("ReplyApproval.keyboardCompact")
    }

    private func sentCard(_ result: ReplyApprovalResult) -> some View {
        HStack(alignment: .center, spacing: DSSpacing.m) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("「\(result.actionLabel)」を送信しました")
                    .font(DSFont.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                if result.remainingCount > 0 {
                    Text("次の対応待ち（残り \(result.remainingCount)）")
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if result.remainingCount > 0 {
                Button("次へ ›", action: onShowNext)
                    .font(DSFont.captionStrong)
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, DSSpacing.l)
        .padding(.trailing, DSSpacing.s)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .glassSurface(.card)
        .accessibilityIdentifier("ReplyApproval.sent")
    }

    private func arm() async {
        isArmed = false
        armProgress = 0
        let presentedAt = Date()
        withAnimation(.linear(duration: ReplyApprovalPolicy.armDelay)) {
            armProgress = 1
        }
        do {
            try await Task.sleep(for: .milliseconds(600))
        } catch is CancellationError {
            return
        } catch {
            assertionFailure("承認カードの待機が失敗しました: \(error)")
            return
        }
        guard ReplyApprovalPolicy.isArmed(presentedAt: presentedAt, now: Date()) else { return }
        isArmed = true
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
