import SwiftUI
import DesignSystemIOS
import PhloxCore
import ChatRenderKit
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
    let maxContentHeight: CGFloat

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
        initiallyShowsDiff: Bool = false,
        maxContentHeight: CGFloat = 360
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
        self.maxContentHeight = maxContentHeight
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
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            header(approval)
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    Text(approval.subject)
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(DSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    if let explanation = approval.explanation {
                        Text(explanation)
                            .font(DSFont.subheadline)
                            .foregroundStyle(DSColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !approval.diffFiles.isEmpty {
                        diffSection(approval)
                    }
                }
            }
            .frame(maxHeight: maxContentHeight)
            .fixedSize(horizontal: false, vertical: true)
            decisionButtons(for: approval)
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.card)
        .opacity(0.4 + 0.6 * armProgress)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(approval.kindLabel.map { "承認待ち · \($0)" } ?? "承認待ち")
        .accessibilityIdentifier("ReplyApprovalCard")
    }

    @ViewBuilder
    private func header(_ approval: ReplyApproval) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedHeader(approval)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s) {
                    approvalKindLabel(approval)
                    if count > 1 { pager }
                    sinceText(approval)
                }
                .fixedSize(horizontal: true, vertical: false)
                stackedHeader(approval)
            }
        }
    }

    private func stackedHeader(_ approval: ReplyApproval) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s) {
                approvalKindLabel(approval)
                Spacer(minLength: DSSpacing.xs)
                if count > 1 { pager }
            }
            sinceText(approval)
        }
    }

    private func approvalKindLabel(_ approval: ReplyApproval) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s) {
            RoundedRectangle(cornerRadius: 2)
                .fill(IOSColor.status.approval)
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(45))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                .accessibilityHidden(true)
            Text(approval.kindLabel.map { "承認待ち · \($0)" } ?? "承認待ち")
                .font(DSFont.inputBar(.caption, for: dynamicTypeSize).weight(.medium))
                .foregroundStyle(IOSColor.status.approval)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sinceText(_ approval: ReplyApproval) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(ReplyApprovalPolicy.sinceText(startedAt: approval.requestedAt, now: context.date))
                .font(DSFont.inputBar(.caption, for: dynamicTypeSize))
                .foregroundStyle(DSColor.textSecondary)
                .monospacedDigit()
                .fixedSize()
        }
    }

    private var pager: some View {
        HStack(spacing: DSSpacing.xs) {
            Button(action: onPrevious) {
                Text("‹")
                    .font(DSFont.iconSend)
                    .dynamicTypeSize(.large)
                    .foregroundStyle(index > 1 ? DSColor.textPrimary : DSColor.textTertiary)
                    .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressFeedbackStyle())
            .disabled(index <= 1)
            .accessibilityLabel("前の承認")
            Text("\(index)/\(count)")
                .font(DSFont.inputBar(.caption, for: dynamicTypeSize))
                .foregroundStyle(DSColor.textSecondary)
                .monospacedDigit()
                .fixedSize()
            Button(action: onNext) {
                Text("›")
                    .font(DSFont.iconSend)
                    .dynamicTypeSize(.large)
                    .foregroundStyle(index < count ? DSColor.textPrimary : DSColor.textTertiary)
                    .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressFeedbackStyle())
            .disabled(index >= count)
            .accessibilityLabel("次の承認")
        }
    }

    private func decisionButtons(for approval: ReplyApproval) -> some View {
        VStack(spacing: DSSpacing.s) {
            HStack(spacing: DSSpacing.s) {
                decisionButton(.accept)
                if approval.allowsSessionScope {
                    decisionButton(.acceptForSession)
                }
            }
            HStack(spacing: DSSpacing.s) {
                decisionButton(.decline)
                decisionButton(.cancel)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func decisionButton(_ decision: ApprovalDecision) -> some View {
        let isPrimary = decision == .accept
        let title = SessionDetailViewModel.replyApprovalActionLabel(decision)
        return Button {
            guard isArmed, !isResponding else { return }
            onDecision(decision)
        } label: {
            Text(title)
                .font((dynamicTypeSize.isAccessibilitySize ? DSFont.inputBar(.chip, for: dynamicTypeSize) : DSFont.body).weight(isPrimary ? .semibold : .medium))
                .foregroundStyle(buttonForeground(for: decision))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DSSpacing.s)
                .padding(.vertical, DSSpacing.s)
                .frame(minWidth: DSTouch.minSize, maxWidth: .infinity, minHeight: 46)
                .background(buttonBackground(for: decision), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(DSPressFeedbackStyle())
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
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isDiffVisible.toggle()
                expandedDiffFiles = isDiffVisible ? [0] : []
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: isDiffVisible ? "chevron.down" : "chevron.right")
                        .font(DSFont.iosCaption.weight(.semibold))
                    Text("差分を見る（\(approval.diffFiles.count) ファイル）")
                        .font(DSFont.body.weight(.medium))
                }
                .foregroundStyle(DSColor.textPrimary)
                .frame(minHeight: DSTouch.minSize, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressFeedbackStyle())
            .accessibilityIdentifier("ReplyApproval.showDiff")
            DSDisclosureContent(isExpanded: isDiffVisible) {
                VStack(spacing: 0) {
                    ForEach(Array(approval.diffFiles.enumerated()), id: \.offset) { offset, file in
                        approvalDiffFile(file, isExpanded: expandedDiffFiles.contains(offset)) {
                            if expandedDiffFiles.contains(offset) {
                                expandedDiffFiles.remove(offset)
                            } else {
                                expandedDiffFiles.insert(offset)
                            }
                        }
                    }
                }
                .background(IOSColor.bg.code, in: RoundedRectangle(cornerRadius: DSRadius.m))
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.m).stroke(IOSColor.bg.separator, lineWidth: 1))
                .padding(.top, DSSpacing.s)
            }
        }
    }

    private func compactCard(_ approval: ReplyApproval) -> some View {
        let title = approval.compactTitle
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.s))
            : AnyLayout(HStackLayout(spacing: DSSpacing.s))
        return layout {
            Text(title)
                .font(DSFont.iosCaption.weight(.medium))
                .foregroundStyle(approval.kindLabel == nil ? DSColor.textPrimary : IOSColor.status.approval)
                .lineLimit(isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: isAccessibilitySize)
                .truncationMode(.middle)
                .accessibilityLabel(approval.compactAccessibilityLabel)
            if !isAccessibilitySize { Spacer(minLength: 0) }
            Button("表示", action: hideKeyboard)
                .font(DSFont.iosCaption.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
                .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                .buttonStyle(DSPressFeedbackStyle())
                .frame(maxWidth: isAccessibilitySize ? .infinity : nil, alignment: .trailing)
        }
        .padding(.leading, DSSpacing.m)
        .padding(.trailing, DSSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 48)
        .glassSurface(.card)
        .accessibilityIdentifier("ReplyApproval.keyboardCompact")
    }

    private func approvalDiffFile(_ file: ChatFileChange, isExpanded: Bool, onToggle: @escaping () -> Void) -> some View {
        let data = SessionDetailDiffCodeViewData(change: file)
        return VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: DSSpacing.s) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    Text(file.path)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    ForEach(data.countBadges) { badge in
                        Text(badge.text)
                            .foregroundStyle(badge.kind == .addition ? DSColor.diffAdded : DSColor.diffRemoved)
                            .fixedSize()
                    }
                }
                .font(DSFont.campMonoCaption)
                .foregroundStyle(IOSColor.text.primary)
                .padding(.horizontal, DSSpacing.s)
                .frame(minHeight: DSTouch.minSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressFeedbackStyle())
            DSDisclosureContent(isExpanded: isExpanded) {
                ReplyApprovalDiffContent(diff: file.diff)
            }
        }
    }

    private func sentCard(_ result: ReplyApprovalResult) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text("「\(result.actionLabel)」を送信しました")
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(IOSColor.status.success)
            if result.remainingCount > 0 {
                Rectangle().fill(IOSColor.bg.separator).frame(height: 1)
                HStack(spacing: DSSpacing.m) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("次の対応待ち（残り \(result.remainingCount)）")
                            .font(DSFont.subheadline)
                            .foregroundStyle(DSColor.textSecondary)
                        if let name = result.nextName, let status = result.nextStatusLabel {
                            (Text("\(name) · ").foregroundStyle(IOSColor.text.primary)
                             + Text(status).foregroundStyle(nextStatusColor(result)))
                                .font(DSFont.body.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("次へ ›", action: onShowNext)
                        .font(DSFont.body.weight(.semibold))
                        .foregroundStyle(IOSColor.accentOnFill)
                        .padding(.horizontal, DSSpacing.l)
                        .frame(minHeight: DSTouch.minSize)
                        .background(IOSColor.accent, in: Capsule())
                        .buttonStyle(DSPressFeedbackStyle())
                        .disabled(isResponding)
                }
            }
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .glassSurface(.card)
        .accessibilityIdentifier("ReplyApproval.sent")
    }

    private func nextStatusColor(_ result: ReplyApprovalResult) -> Color {
        switch result.nextAttention?.displayState {
        case .error: IOSColor.status.error
        case .stalled: IOSColor.status.stalled
        case .question: IOSColor.status.question
        default: result.nextIsQuestion ? IOSColor.status.question : IOSColor.status.approval
        }
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

struct ReplyApprovalDiffContent: View {
    let diff: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) { rows }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ChatDiffClassifier.classify(diff).filter { $0.isDisplayable && $0.kind != .hunk }) { line in
                HStack(spacing: DSSpacing.s) {
                    Text(line.oldLineNumber.map(String.init) ?? "−")
                        .foregroundStyle(IOSColor.text.tertiary)
                        .frame(minWidth: 24, alignment: .trailing)
                    Text(line.newLineNumber.map(String.init) ?? "−")
                        .foregroundStyle(IOSColor.text.tertiary)
                        .frame(minWidth: 24, alignment: .trailing)
                    Text(line.text)
                        .foregroundStyle(IOSColor.text.primary)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(DSFont.campMonoCaption)
                .padding(.horizontal, DSSpacing.s)
                .frame(maxWidth: .infinity, minHeight: 19, alignment: .leading)
                .background(line.kind == .addition ? DSColor.diffAdded.opacity(0.12) : line.kind == .deletion ? DSColor.diffRemoved.opacity(0.12) : .clear)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
