// task-40（UI-03）の受け入れテスト。
//
// ベースラインでの red 理由: `TranscriptTypography` は本タスクが新設を要求する API で、
// baseline_commit には存在しない（参照未解決でコンパイル不能＝red）。
//
// 契約: 役割から文字指定と間隔を返す正本。期待値は下表の独立リテラルであり、
// 実装の `allCases` や Style 一覧から生成しない。

import CoreGraphics
import Testing
@testable import DesignSystem

@Suite("task-40: transcript typography")
struct AcceptanceTranscriptTypographyTests {
    /// 契約「文字の正本」Role 表。実装の `allCases` から作らない。
    private static let expectedRoles: [TranscriptTypography.Role] = [
        .body, .bodyStrong, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6,
        .processSummary, .metadata, .metadataStrong, .code, .codeMetadata, .inlineCode,
    ]

    /// 契約 Role 表の基準 pt。`style(for:).baseSize` からコピーしない。
    private static let expectedBaseSizes: [(TranscriptTypography.Role, CGFloat)] = [
        (.body, 15),
        (.bodyStrong, 15),
        (.heading1, 26),
        (.heading2, 19),
        (.heading3, 16),
        (.heading4, 15),
        (.heading5, 15),
        (.heading6, 15),
        (.processSummary, 15),
        (.metadata, 10),
        (.metadataStrong, 10),
        (.code, 13),
        (.codeMetadata, 10),
        (.inlineCode, 13.5),
    ]

    @Test("Role は CaseIterable・Equatable・Sendable で、集合が契約表 14 役割と一致する")
    func roleSetMatchesFrozenTable() {
        requireRoleTraits(TranscriptTypography.Role.self)
        #expect(Self.expectedRoles.count == 14)
        #expect(Set(Self.expectedRoles).count == 14)
        #expect(TranscriptTypography.Role.allCases.count == 14)
        #expect(Set(TranscriptTypography.Role.allCases) == Set(Self.expectedRoles))
        for (index, expected) in Self.expectedRoles.enumerated() {
            #expect(
                TranscriptTypography.Role.allCases.contains(expected),
                Comment(rawValue: "role[\(index)]")
            )
        }
    }

    @Test("各 Style のサイズ・太さ・design・ink が契約表の独立リテラルと一致する")
    func styleFieldsMatchFrozenTable() {
        let body = TranscriptTypography.style(for: .body)
        #expect(body.baseSize == 15, Comment(rawValue: "body size"))
        #expect(body.weight == .regular, Comment(rawValue: "body weight"))
        #expect(body.design == .system, Comment(rawValue: "body design"))
        #expect(body.ink == .primary, Comment(rawValue: "body ink"))

        let bodyStrong = TranscriptTypography.style(for: .bodyStrong)
        #expect(bodyStrong.baseSize == 15, Comment(rawValue: "bodyStrong size"))
        #expect(bodyStrong.weight == .semibold, Comment(rawValue: "bodyStrong weight"))
        #expect(bodyStrong.design == .system, Comment(rawValue: "bodyStrong design"))
        #expect(bodyStrong.ink == .primary, Comment(rawValue: "bodyStrong ink"))

        let heading1 = TranscriptTypography.style(for: .heading1)
        #expect(heading1.baseSize == 26, Comment(rawValue: "heading1 size"))
        #expect(heading1.weight == .bold, Comment(rawValue: "heading1 weight"))
        #expect(heading1.design == .system, Comment(rawValue: "heading1 design"))
        #expect(heading1.ink == .primary, Comment(rawValue: "heading1 ink"))

        let heading2 = TranscriptTypography.style(for: .heading2)
        #expect(heading2.baseSize == 19, Comment(rawValue: "heading2 size"))
        #expect(heading2.weight == .bold, Comment(rawValue: "heading2 weight"))
        #expect(heading2.design == .system, Comment(rawValue: "heading2 design"))
        #expect(heading2.ink == .primary, Comment(rawValue: "heading2 ink"))

        let heading3 = TranscriptTypography.style(for: .heading3)
        #expect(heading3.baseSize == 16, Comment(rawValue: "heading3 size"))
        #expect(heading3.weight == .semibold, Comment(rawValue: "heading3 weight"))
        #expect(heading3.design == .system, Comment(rawValue: "heading3 design"))
        #expect(heading3.ink == .primary, Comment(rawValue: "heading3 ink"))

        let heading4 = TranscriptTypography.style(for: .heading4)
        #expect(heading4.baseSize == 15, Comment(rawValue: "heading4 size"))
        #expect(heading4.weight == .semibold, Comment(rawValue: "heading4 weight"))
        #expect(heading4.design == .system, Comment(rawValue: "heading4 design"))
        #expect(heading4.ink == .primary, Comment(rawValue: "heading4 ink"))

        let heading5 = TranscriptTypography.style(for: .heading5)
        #expect(heading5.baseSize == 15, Comment(rawValue: "heading5 size"))
        #expect(heading5.weight == .semibold, Comment(rawValue: "heading5 weight"))
        #expect(heading5.design == .system, Comment(rawValue: "heading5 design"))
        #expect(heading5.ink == .primary, Comment(rawValue: "heading5 ink"))

        let heading6 = TranscriptTypography.style(for: .heading6)
        #expect(heading6.baseSize == 15, Comment(rawValue: "heading6 size"))
        #expect(heading6.weight == .semibold, Comment(rawValue: "heading6 weight"))
        #expect(heading6.design == .system, Comment(rawValue: "heading6 design"))
        #expect(heading6.ink == .primary, Comment(rawValue: "heading6 ink"))

        let processSummary = TranscriptTypography.style(for: .processSummary)
        #expect(processSummary.baseSize == 15, Comment(rawValue: "processSummary size"))
        #expect(processSummary.weight == .semibold, Comment(rawValue: "processSummary weight"))
        #expect(processSummary.design == .system, Comment(rawValue: "processSummary design"))
        #expect(processSummary.ink == .tool, Comment(rawValue: "processSummary ink"))

        let metadata = TranscriptTypography.style(for: .metadata)
        #expect(metadata.baseSize == 10, Comment(rawValue: "metadata size"))
        #expect(metadata.weight == .regular, Comment(rawValue: "metadata weight"))
        #expect(metadata.design == .system, Comment(rawValue: "metadata design"))
        #expect(metadata.ink == .secondary, Comment(rawValue: "metadata ink"))

        let metadataStrong = TranscriptTypography.style(for: .metadataStrong)
        #expect(metadataStrong.baseSize == 10, Comment(rawValue: "metadataStrong size"))
        #expect(metadataStrong.weight == .medium, Comment(rawValue: "metadataStrong weight"))
        #expect(metadataStrong.design == .system, Comment(rawValue: "metadataStrong design"))
        #expect(metadataStrong.ink == .secondary, Comment(rawValue: "metadataStrong ink"))

        let code = TranscriptTypography.style(for: .code)
        #expect(code.baseSize == 13, Comment(rawValue: "code size"))
        #expect(code.weight == .regular, Comment(rawValue: "code weight"))
        #expect(code.design == .monospaced, Comment(rawValue: "code design"))
        #expect(code.ink == .primary, Comment(rawValue: "code ink"))

        let codeMetadata = TranscriptTypography.style(for: .codeMetadata)
        #expect(codeMetadata.baseSize == 10, Comment(rawValue: "codeMetadata size"))
        #expect(codeMetadata.weight == .regular, Comment(rawValue: "codeMetadata weight"))
        #expect(codeMetadata.design == .monospaced, Comment(rawValue: "codeMetadata design"))
        #expect(codeMetadata.ink == .secondary, Comment(rawValue: "codeMetadata ink"))

        let inlineCode = TranscriptTypography.style(for: .inlineCode)
        #expect(inlineCode.baseSize == 13.5, Comment(rawValue: "inlineCode size"))
        #expect(inlineCode.weight == .regular, Comment(rawValue: "inlineCode weight"))
        #expect(inlineCode.design == .monospaced, Comment(rawValue: "inlineCode design"))
        #expect(inlineCode.ink == .accent, Comment(rawValue: "inlineCode ink"))
    }

    @Test("倍率 0.8 / 1.0 / 1.5 / 2.0 で pointSize は基準値×倍率")
    func pointSizeIsBaseTimesScale() {
        let scales: [CGFloat] = [0.8, 1.0, 1.5, 2.0]
        for (role, base) in Self.expectedBaseSizes {
            for scale in scales {
                #expect(
                    TranscriptTypography.pointSize(for: role, scale: scale) == base * scale,
                    Comment(rawValue: "\(role) @ \(scale)")
                )
            }
        }
    }

    @Test("同一倍率で H1 ≥ H2 ≥ H3 ≥ H4＝H5＝H6＝body＝processSummary > metadata")
    func headingAndBodyOrdering() {
        let scales: [CGFloat] = [0.8, 1.0, 1.5, 2.0]
        for scale in scales {
            let h1 = TranscriptTypography.pointSize(for: .heading1, scale: scale)
            let h2 = TranscriptTypography.pointSize(for: .heading2, scale: scale)
            let h3 = TranscriptTypography.pointSize(for: .heading3, scale: scale)
            let h4 = TranscriptTypography.pointSize(for: .heading4, scale: scale)
            let h5 = TranscriptTypography.pointSize(for: .heading5, scale: scale)
            let h6 = TranscriptTypography.pointSize(for: .heading6, scale: scale)
            let body = TranscriptTypography.pointSize(for: .body, scale: scale)
            let process = TranscriptTypography.pointSize(for: .processSummary, scale: scale)
            let metadata = TranscriptTypography.pointSize(for: .metadata, scale: scale)
            #expect(h1 >= h2, Comment(rawValue: "h1>=h2 @ \(scale)"))
            #expect(h2 >= h3, Comment(rawValue: "h2>=h3 @ \(scale)"))
            #expect(h3 >= h4, Comment(rawValue: "h3>=h4 @ \(scale)"))
            #expect(h4 == h5, Comment(rawValue: "h4==h5 @ \(scale)"))
            #expect(h5 == h6, Comment(rawValue: "h5==h6 @ \(scale)"))
            #expect(h4 == body, Comment(rawValue: "h4==body @ \(scale)"))
            #expect(body == process, Comment(rawValue: "body==process @ \(scale)"))
            #expect(process > metadata, Comment(rawValue: "process>metadata @ \(scale)"))
        }
    }

    @Test("bodyStrong と body のサイズは同じで、太さが区別される")
    func bodyStrongDiffersOnlyInWeight() {
        let body = TranscriptTypography.style(for: .body)
        let strong = TranscriptTypography.style(for: .bodyStrong)
        #expect(body.baseSize == 15)
        #expect(strong.baseSize == 15)
        #expect(body.baseSize == strong.baseSize)
        #expect(TranscriptTypography.pointSize(for: .body, scale: 1.5)
            == TranscriptTypography.pointSize(for: .bodyStrong, scale: 1.5))
        #expect(body.weight == .regular)
        #expect(strong.weight == .semibold)
        #expect(body.weight != strong.weight)
        #expect(body.design == strong.design)
        #expect(body.ink == strong.ink)
    }

    @Test("code＝13、inlineCode＝13.5、codeMetadata＝10 の基準値と等幅指定")
    func codeRolesAreMonospacedAtFrozenSizes() {
        let code = TranscriptTypography.style(for: .code)
        let inlineCode = TranscriptTypography.style(for: .inlineCode)
        let codeMetadata = TranscriptTypography.style(for: .codeMetadata)
        #expect(code.baseSize == 13)
        #expect(inlineCode.baseSize == 13.5)
        #expect(codeMetadata.baseSize == 10)
        #expect(code.design == .monospaced)
        #expect(inlineCode.design == .monospaced)
        #expect(codeMetadata.design == .monospaced)
        #expect(TranscriptTypography.pointSize(for: .code, scale: 1.0) == 13)
        #expect(TranscriptTypography.pointSize(for: .inlineCode, scale: 1.0) == 13.5)
        #expect(TranscriptTypography.pointSize(for: .codeMetadata, scale: 1.0) == 10)
    }

    @Test("間隔の値と majorSection > betweenAnswers > withinAnswer > metadataGap")
    func spacingConstantsMatchFrozenTable() {
        #expect(TranscriptTypography.withinAnswer == 8)
        #expect(TranscriptTypography.betweenAnswers == 16)
        #expect(TranscriptTypography.majorSection == 24)
        #expect(TranscriptTypography.metadataGap == 4)
        #expect(TranscriptTypography.textLineSpacing == 4)
        #expect(TranscriptTypography.cardHorizontalInset == 12)
        #expect(TranscriptTypography.cardVerticalInset == 8)
        #expect(TranscriptTypography.codeContentInset == 12)
        #expect(TranscriptTypography.transcriptHorizontalInset == 16)
        #expect(TranscriptTypography.transcriptVerticalInset == 12)

        #expect(TranscriptTypography.withinAnswer == DSSpacing.s)
        #expect(TranscriptTypography.betweenAnswers == DSSpacing.l)
        #expect(TranscriptTypography.majorSection == DSSpacing.xl)
        #expect(TranscriptTypography.metadataGap == DSSpacing.xs)
        #expect(TranscriptTypography.textLineSpacing == DSSpacing.xs)
        #expect(TranscriptTypography.cardHorizontalInset == DSSpacing.m)
        #expect(TranscriptTypography.cardVerticalInset == DSSpacing.s)
        #expect(TranscriptTypography.codeContentInset == DSSpacing.m)
        #expect(TranscriptTypography.transcriptHorizontalInset == DSSpacing.l)
        #expect(TranscriptTypography.transcriptVerticalInset == DSSpacing.m)

        #expect(TranscriptTypography.majorSection > TranscriptTypography.betweenAnswers)
        #expect(TranscriptTypography.betweenAnswers > TranscriptTypography.withinAnswer)
        #expect(TranscriptTypography.withinAnswer > TranscriptTypography.metadataGap)
    }

    @Test("gap の 20 条件が契約表どおりで、文字倍率を変えても間隔値は変わらない")
    func gapTwentyCellsAreFrozenAndScaleInvariant() {
        let expected: [(TranscriptTypography.BlockRole?, TranscriptTypography.BlockRole, CGFloat)] = [
            (nil, .user, 0),
            (nil, .answer, 0),
            (nil, .process, 0),
            (nil, .auxiliary, 0),
            (.user, .user, 24),
            (.user, .answer, 16),
            (.user, .process, 16),
            (.user, .auxiliary, 16),
            (.answer, .user, 24),
            (.answer, .answer, 8),
            (.answer, .process, 8),
            (.answer, .auxiliary, 8),
            (.process, .user, 24),
            (.process, .answer, 16),
            (.process, .process, 8),
            (.process, .auxiliary, 8),
            (.auxiliary, .user, 24),
            (.auxiliary, .answer, 16),
            (.auxiliary, .process, 8),
            (.auxiliary, .auxiliary, 8),
        ]
        #expect(expected.count == 20)
        for (after, before, value) in expected {
            #expect(
                TranscriptTypography.gap(after: after, before: before) == value,
                Comment(rawValue: "\(String(describing: after))->\(before)")
            )
        }
        #expect(TranscriptTypography.gap(after: .user, before: .answer) == TranscriptTypography.betweenAnswers)
        #expect(TranscriptTypography.gap(after: .answer, before: .answer) == TranscriptTypography.withinAnswer)
        #expect(TranscriptTypography.gap(after: .answer, before: .user) == TranscriptTypography.majorSection)
        #expect(TranscriptTypography.gap(after: nil, before: .user) == 0)
        #expect(TranscriptTypography.gap(after: .user, before: .answer) == 16)
        #expect(TranscriptTypography.gap(after: .answer, before: .answer) == 8)
        #expect(TranscriptTypography.gap(after: .auxiliary, before: .user) == 24)
    }
}

private func requireRoleTraits<T: CaseIterable & Equatable & Sendable>(_: T.Type) {}
