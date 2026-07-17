// task-2 白箱テスト — ブランチ名ラベルの幅クランプ排除と圧縮挙動。

import AppKit
import SwiftUI
import Testing
import StructuredChatKit
@testable import SessionFeature

@Suite("Composer branch label whitebox", .serialized)
struct ComposerBranchLabelWhiteboxTests {
    private let longBranchName = "feature/composer-overflow-with-extra-segments"
    private let epsilon: CGFloat = 1
    private let footerSpacing: CGFloat = 8

    @Test
    func branchNameMaxWidth_isNilForBothLayouts() {
        #expect(ComposerIndicatorMetrics.branchNameMaxWidth(for: .regular) == nil)
        #expect(ComposerIndicatorMetrics.branchNameMaxWidth(for: .compact) == nil)
    }

    @Test @MainActor
    func compactLayout_longBranchUsesMoreThanLegacyClampAtWideProposedWidth() throws {
        let legacyClamp: CGFloat = 100
        let proposedWidth: CGFloat = 280
        let renderedSize = try renderSize(
            ComposerContextIndicator(
                usage: nil,
                workspacePath: "",
                layout: .compact,
                branchNameOverride: longBranchName
            ),
            proposedWidth: proposedWidth
        )
        // 旧 100pt 固定クランプより広い提案幅では、それ以上の幅を使う（全文表示）。
        #expect(renderedSize.width > legacyClamp + epsilon)
    }

    @Test @MainActor
    func compactLayout_longBranchRendersWithinNarrowProposedWidth() throws {
        let proposedWidth: CGFloat = 160
        let renderedSize = try renderSize(
            ComposerContextIndicator(
                usage: TurnUsage(contextUsedTokens: 1, contextWindowTokens: 100),
                workspacePath: "",
                layout: .compact,
                branchNameOverride: longBranchName,
                branchIsCheckingOutOverride: true
            ),
            proposedWidth: proposedWidth
        )
        #expect(renderedSize.width <= proposedWidth + epsilon)
    }

    @Test @MainActor
    func compactLayout_checkingOutSpinnerDoesNotExpandBeyondProposedWidth() throws {
        let proposedWidth: CGFloat = 140
        let renderedSize = try renderSize(
            ComposerContextIndicator(
                usage: nil,
                workspacePath: "",
                layout: .compact,
                branchNameOverride: longBranchName,
                branchIsCheckingOutOverride: true
            ),
            proposedWidth: proposedWidth
        )
        #expect(renderedSize.width <= proposedWidth + epsilon)
    }

    @Test @MainActor
    func footerHarness_indicatorClaimsIdealWidthWhenSlackExistsButHalfSplitWouldTruncate() throws {
        let idealLabelWidth = try intrinsicWidth(branchName: longBranchName)
        let trailingRigidWidth: CGFloat = 120
        // 残余 R は idealLabel 以上あるが R/2 では idealLabel 未満 — 50/50 分割だと省略されうる中間幅。
        let proposedWidth = idealLabelWidth + trailingRigidWidth + footerSpacing + (idealLabelWidth * 0.4)

        let allocatedWidth = measureIndicatorWidthInFooterHarness(
            branchName: longBranchName,
            proposedWidth: proposedWidth,
            leadingRigidWidth: 0,
            trailingRigidWidth: trailingRigidWidth
        )

        #expect(allocatedWidth >= idealLabelWidth - epsilon)
    }

    @Test @MainActor
    func footerHarness_indicatorClaimsIdealWidthWithLeadingSettingsRigidWidth() throws {
        let idealLabelWidth = try intrinsicWidth(branchName: longBranchName)
        let leadingRigidWidth: CGFloat = 88
        let trailingRigidWidth: CGFloat = 120
        let proposedWidth = leadingRigidWidth + idealLabelWidth + trailingRigidWidth
            + (footerSpacing * 3) + (idealLabelWidth * 0.25)

        let allocatedWidth = measureIndicatorWidthInFooterHarness(
            branchName: longBranchName,
            proposedWidth: proposedWidth,
            leadingRigidWidth: leadingRigidWidth,
            trailingRigidWidth: trailingRigidWidth
        )

        #expect(allocatedWidth >= idealLabelWidth - epsilon)
    }

    @Test @MainActor
    func footerHarness_indicatorShrinksOnlyWhenProposedWidthInsufficient() throws {
        let idealLabelWidth = try intrinsicWidth(branchName: longBranchName)
        let trailingRigidWidth: CGFloat = 120
        let proposedWidth = trailingRigidWidth + (footerSpacing * 2) + 36

        let allocatedWidth = measureIndicatorWidthInFooterHarness(
            branchName: longBranchName,
            proposedWidth: proposedWidth,
            leadingRigidWidth: 0,
            trailingRigidWidth: trailingRigidWidth
        )

        #expect(allocatedWidth > 0)
        #expect(allocatedWidth < idealLabelWidth - epsilon)
    }

    @Test @MainActor
    func footerHarness_rigidTrailingControlsStayWithinProposedWidth() throws {
        let trailingRigidWidth: CGFloat = 120
        let leadingRigidWidth: CGFloat = 88
        let proposedWidth: CGFloat = 360

        let renderedSize = try renderSize(
            footerHarness(
                branchName: longBranchName,
                leadingRigidWidth: leadingRigidWidth,
                trailingRigidWidth: trailingRigidWidth
            ),
            proposedWidth: proposedWidth
        )

        #expect(renderedSize.width <= proposedWidth + epsilon)
    }

    @MainActor
    private func footerHarness(
        branchName: String,
        leadingRigidWidth: CGFloat,
        trailingRigidWidth: CGFloat
    ) -> some View {
        HStack(spacing: footerSpacing) {
            Color.clear.frame(width: leadingRigidWidth)
            ComposerContextIndicator(
                usage: nil,
                workspacePath: "",
                layout: .compact,
                branchNameOverride: branchName
            )
            Spacer(minLength: footerSpacing)
            Color.clear.frame(width: trailingRigidWidth)
        }
    }

    @MainActor
    private func measureIndicatorWidthInFooterHarness(
        branchName: String,
        proposedWidth: CGFloat,
        leadingRigidWidth: CGFloat,
        trailingRigidWidth: CGFloat
    ) -> CGFloat {
        let widthStorage = IndicatorWidthStorage()
        let harness = FooterBranchWiringHarness(
            branchName: branchName,
            proposedWidth: proposedWidth,
            leadingRigidWidth: leadingRigidWidth,
            trailingRigidWidth: trailingRigidWidth,
            footerSpacing: footerSpacing,
            widthStorage: widthStorage
        )

        let hostingView = NSHostingView(rootView: harness)
        hostingView.frame = CGRect(x: 0, y: 0, width: proposedWidth, height: 44)
        hostingView.layoutSubtreeIfNeeded()
        return widthStorage.width
    }

    @MainActor
    private func renderSize<Content: View>(_ content: Content, proposedWidth: CGFloat) throws -> CGSize {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: proposedWidth, height: nil)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        return image.size
    }

    /// ブランチラベルの「真の自然幅」（全文テキスト＋アイコンの ideal 幅）を計測する。
    /// indicator 全体は maxWidth:.infinity で提案幅いっぱいまで貪欲に伸びるため、
    /// infinity frame を持たない ComposerBranchLabelContent 単体を計測する
    /// （50/50 分割リグレッションの検出には、貪欲取得後の幅でなく真のテキスト幅が基準に要る）。
    @MainActor
    private func naturalIndicatorWidth(branchName: String) -> CGFloat {
        let widthStorage = IndicatorWidthStorage()
        let view = HStack {
            ComposerBranchLabelContent(
                currentBranch: branchName,
                layout: .compact,
                isCheckingOut: false
            )
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: MeasuredSubviewWidthKey.self,
                        value: geometry.size.width
                    )
                }
            )
            Spacer()
        }
        .frame(width: 2_000)
        .onPreferenceChange(MeasuredSubviewWidthKey.self) { width in
            widthStorage.width = width
        }

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: 2_000, height: 44)
        hostingView.layoutSubtreeIfNeeded()
        return widthStorage.width
    }

    @MainActor
    private func intrinsicWidth(branchName: String) throws -> CGFloat {
        let width = naturalIndicatorWidth(branchName: branchName)
        return try #require(width > 0 ? width : nil)
    }
}

@MainActor
private final class IndicatorWidthStorage {
    var width: CGFloat = 0
}

private struct MeasuredSubviewWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// `ChatComposerFooter.regularFooter` と同型の HStack 配線（設定・停止・送信は剛性幅で代替）。
private struct FooterBranchWiringHarness: View {
    let branchName: String
    let proposedWidth: CGFloat
    let leadingRigidWidth: CGFloat
    let trailingRigidWidth: CGFloat
    let footerSpacing: CGFloat
    let widthStorage: IndicatorWidthStorage

    var body: some View {
        HStack(spacing: footerSpacing) {
            if leadingRigidWidth > 0 {
                Color.clear.frame(width: leadingRigidWidth)
            }
            ComposerContextIndicator(
                usage: nil,
                workspacePath: "",
                layout: .compact,
                branchNameOverride: branchName
            )
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: MeasuredSubviewWidthKey.self,
                        value: geometry.size.width
                    )
                }
            )
            Spacer(minLength: footerSpacing)
            Color.clear.frame(width: trailingRigidWidth)
        }
        .frame(width: proposedWidth, alignment: .leading)
        .onPreferenceChange(MeasuredSubviewWidthKey.self) { width in
            widthStorage.width = width
        }
    }
}
