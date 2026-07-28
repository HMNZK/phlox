import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite
struct TranscriptRenderBudgetWhiteboxTests {
    private let timestamp = Date(timeIntervalSince1970: 0)

    @Test
    func measuredConstantsAreFixed() {
        #expect(TranscriptRenderBudget.diffLineUnits == 41)
        #expect(TranscriptRenderBudget.textCharacterUnits == 5)
        #expect(TranscriptRenderBudget.otherBlockUnits == 50)
        #expect(TranscriptRenderBudget.defaultUnits == 9_300)
        #expect(TranscriptRenderBudget.minimumBlocks == 6)
    }

    @Test
    func emptyBlocksAllowZero() {
        #expect(
            TranscriptRenderBudget.allowedBlockCount(
                blocks: [],
                requestedLimit: 50,
                defaultLimit: 50,
                minimumBlocks: 6
            ) == 0
        )
    }

    @Test
    func singleOverBudgetBlockIsStillAllowed() {
        let blocks = [textBlock(id: "heavy", characterCount: 2_000)]

        #expect(
            TranscriptRenderBudget.allowedBlockCount(
                blocks: blocks,
                requestedLimit: 1,
                defaultLimit: 50,
                minimumBlocks: 0
            ) == 1
        )
    }

    @Test
    func lightBlocksAreNotClampedBelowRequestedLimit() {
        let blocks = (0..<80).map { textBlock(id: "m\($0)", characterCount: 1) }

        #expect(
            TranscriptRenderBudget.allowedBlockCount(
                blocks: blocks,
                requestedLimit: 50,
                defaultLimit: 50,
                minimumBlocks: 6
            ) == 50
        )
    }

    @Test
    func oneExpansionDoesNotDoubleALightDefaultWindowAcrossHeavyOlderDiffs() {
        let heavyOlderDiffs = (0..<50).map { fileChangeBlock(id: "diff\($0)", lineCount: 200) }
        let lightRecentTail = (0..<50).map { textBlock(id: "tail\($0)", characterCount: 1) }
        let blocks = heavyOlderDiffs + lightRecentTail

        let defaultCount = TranscriptRenderBudget.allowedBlockCount(
            blocks: blocks,
            requestedLimit: 50,
            defaultLimit: 50,
            minimumBlocks: 6
        )
        let expandedCount = TranscriptRenderBudget.allowedBlockCount(
            blocks: blocks,
            requestedLimit: 100,
            defaultLimit: 50,
            minimumBlocks: 6
        )

        #expect(defaultCount == 50)
        #expect(expandedCount == defaultCount + 6)
    }

    @Test
    func heavyOldDiffStopsTheSuffixBeforeThatBlock() {
        let oldHeavyDiff = fileChangeBlock(id: "diff", lineCount: 200)
        let lightTail = (0..<30).map { textBlock(id: "tail\($0)", characterCount: 1) }

        #expect(
            TranscriptRenderBudget.allowedBlockCount(
                blocks: [oldHeavyDiff] + lightTail,
                requestedLimit: 31,
                defaultLimit: 50,
                minimumBlocks: 6
            ) == 30
        )
    }

    @Test
    func defaultCollapsedFileChangeOnlyPaysSkeletonWeight() {
        let collapsed = fileChangeBlock(id: "collapsed", lineCount: 201)
        let muchLargerCollapsed = fileChangeBlock(id: "larger", lineCount: 1_000)

        #expect(TranscriptRenderBudget.weight(of: collapsed) == TranscriptRenderBudget.otherBlockUnits)
        #expect(TranscriptRenderBudget.weight(of: muchLargerCollapsed) == TranscriptRenderBudget.otherBlockUnits)
    }

    @Test
    func requestedLimitIsMonotonicAtFixedPoints() {
        let blocks = (0..<300).map { textBlock(id: "m\($0)", characterCount: 40) }
        let requestedLimits = [0, 1, 5, 6, 10, 49, 50, 51, 99, 100, 149, 150, 199, 200, 250]
        let counts = requestedLimits.map {
            TranscriptRenderBudget.allowedBlockCount(
                blocks: blocks,
                requestedLimit: $0,
                defaultLimit: 50,
                minimumBlocks: 6
            )
        }

        #expect(counts == [0, 1, 5, 6, 10, 46, 46, 46, 46, 93, 93, 139, 139, 186, 232])
        for pair in zip(counts, counts.dropFirst()) {
            #expect(pair.0 <= pair.1)
        }
    }

    @Test
    func budgetExhaustionAtDefaultLimitNeverDropsBelowMinimum() {
        let blocks = (0..<10).map { textBlock(id: "heavy\($0)", characterCount: 2_000) }

        #expect(
            TranscriptRenderBudget.allowedBlockCount(
                blocks: blocks,
                requestedLimit: 50,
                defaultLimit: 50,
                minimumBlocks: 6
            ) == 6
        )
    }

    @Test
    func expandingRequestedLimitRaisesMinimumForBlocksFarOverBudget() {
        let blocks = (0..<30).map { textBlock(id: "heavy\($0)", characterCount: 10_000) }
        let requestedLimits = [50, 100, 150]
        let counts = requestedLimits.map {
            TranscriptRenderBudget.allowedBlockCount(
                blocks: blocks,
                requestedLimit: $0,
                defaultLimit: 50,
                minimumBlocks: 6
            )
        }

        #expect(counts == [6, 12, 18])
    }

    @Test
    func pressingLoadEarlierIncreasesVisibleCountWhenBudgetStallsAtDefaultCount() {
        let olderTail = (0..<23).map { textBlock(id: "older\($0)", characterCount: 150) }
        let heavyBoundary = textBlock(id: "heavy-boundary", characterCount: 2_000)
        let recentTail = (0..<12).map { textBlock(id: "recent\($0)", characterCount: 150) }
        let blocks = olderTail + [heavyBoundary] + recentTail
        let requestedLimits = [50, 100, 150]
        let counts = requestedLimits.map {
            TranscriptRenderBudget.allowedBlockCount(
                blocks: blocks,
                requestedLimit: $0,
                defaultLimit: 50,
                minimumBlocks: 6
            )
        }

        #expect(counts == [12, 18, 24])
        for pair in zip(counts, counts.dropFirst()) {
            #expect(pair.1 > pair.0, "押しても表示件数が \(pair.0) から動かない")
        }
    }

    @Test
    func defaultLimitKeepsExistingCountsAcrossWeightProfiles() {
        let lightBlocks = (0..<80).map { textBlock(id: "light\($0)", characterCount: 1) }
        let heavyBlocks = (0..<20).map { textBlock(id: "heavy\($0)", characterCount: 200) }
        let longTextBlocks = (0..<20).map { textBlock(id: "long\($0)", characterCount: 2_000) }

        let counts = [lightBlocks, heavyBlocks, longTextBlocks].map {
            TranscriptRenderBudget.allowedBlockCount(
                blocks: $0,
                requestedLimit: 50,
                defaultLimit: 50,
                minimumBlocks: 6
            )
        }

        #expect(counts == [50, 9, 6])
    }

    @Test
    func textualAndOtherWeightsMatchTheirChatItemCases() {
        let twentyCharacters = String(repeating: "x", count: 20)
        let expectedTextWeight = 20 * TranscriptRenderBudget.textCharacterUnits
        let textualBlocks: [ChatTranscriptBlock] = [
            .single(.agentMessage(id: "a", text: twentyCharacters, timestamp: timestamp)),
            .single(.userMessage(id: "u", text: twentyCharacters, timestamp: timestamp)),
            .single(.reasoning(id: "r", text: twentyCharacters, timestamp: timestamp)),
            .single(.error(id: "e", message: twentyCharacters, timestamp: timestamp)),
        ]

        for block in textualBlocks {
            #expect(TranscriptRenderBudget.weight(of: block) == expectedTextWeight)
        }

        let command = ChatItem.commandExecution(
            id: "c",
            command: "echo",
            output: twentyCharacters,
            timestamp: timestamp
        )
        #expect(
            TranscriptRenderBudget.weight(of: .commandGroup(id: "c", items: [command]))
                == TranscriptRenderBudget.otherBlockUnits
        )
        #expect(
            TranscriptRenderBudget.weight(of: .single(command))
                == TranscriptRenderBudget.otherBlockUnits
        )
    }

    private func textBlock(id: String, characterCount: Int) -> ChatTranscriptBlock {
        .single(
            .agentMessage(
                id: id,
                text: String(repeating: "x", count: characterCount),
                timestamp: timestamp
            )
        )
    }

    private func fileChangeBlock(id: String, lineCount: Int) -> ChatTranscriptBlock {
        let diff = (0..<lineCount).map { "+line \($0)" }.joined(separator: "\n")
        return .single(
            .fileChange(
                id: id,
                changes: [FilePatchChange(path: "\(id).swift", diff: diff)],
                timestamp: timestamp
            )
        )
    }
}
