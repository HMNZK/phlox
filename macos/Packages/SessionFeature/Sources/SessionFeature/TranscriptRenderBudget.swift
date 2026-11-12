/// 非 Lazy の transcript が末尾から描画するブロック数を、実測由来のコストで制限する純関数。
///
/// 2026-07-29 の単一表示 N=50 計測では、diff 行の選択を無効化した後も
/// fileChange が 245ms、agentMessage が 187ms、全セルを空にした骨格が 107ms だった。
/// 係数 41 / 5 / 50 は物理的な単価ではなく、実データを目標 200ms に収めるための較正値。
/// 長文テキストでは 1 文字あたり 0.0125〜0.0167ms（12 ブロック / 31,848 文字で
/// 398ms、20 ブロックで 707ms、40 ブロックで 1,777ms）だった。一方、実データに多い
/// 80〜160 文字程度の本文ブロックでは、アバター行・タイムスタンプ・コピーボタン・
/// Markdown のブロック分割・`.fixedSize` の理想サイズ計測といった固定費が支配的になる。
/// textCharacterUnits = 2 では 256ms、5 では 178ms だったため 5 を採用する。
/// 目標 200ms から骨格の固定費 107ms を引いた残り 93ms を既定予算 9,300 units とする。
///
/// ADR 0030 の再入禁止に従い、スクロール量・可視領域・レイアウト計測値は参照しない。
enum TranscriptRenderBudget {
    /// diff 1 行あたりの較正重み。
    static let diffLineUnits = 41
    /// 本文 1 文字あたりの較正重み。固定費を文字数へ割り振る代理値でもある。
    static let textCharacterUnits = 5
    /// セル骨格など、内容量に比例しない 1 ブロックの最低較正重み。
    static let otherBlockUnits = 50
    /// 実ScrollViewの40操作で較正したカード固定費。8段でも過剰なカードを同時描画させない。
    static let statusCardBaseUnits = 3_000
    /// エージェント状態カードの、タスク・タスク外の行 1 本あたりの重み。
    /// 2026-11-07 の画面外の計測（NSHostingView の初回レイアウト＋描画、10 枚の中央値、release）で、
    /// 短い agentMessage のセル（50 units）を物差しにすると、閉じた行 1 本が約 14 units、開いた作業の行
    /// 1 本が約 27 unitsだった（debug は 12〜19 と 20〜29）。
    /// この相対値はカード更新時の固定費を表さないため、固定費は統合計測のstatusCardBaseUnitsで別に扱う。
    static let statusCardRowUnits = 14
    /// 同、開いている作業の行 1 本あたりの重み（上と同じ計測）。
    static let statusCardEntryUnits = 27
    /// 200ms（目標）- 107ms（骨格固定費）= 93ms。
    static let defaultUnits = 9_300
    /// 最新の会話文脈を失わないために、予算超過時も描画する既定の最低件数。
    static let minimumBlocks = 6

    /// 予算を超えない範囲で、末尾から描画できるブロック数を返す。
    ///
    /// requestedLimit が増える間、候補は末尾側を保ったまま古い側へだけ広がる。
    /// defaultLimit ごとの段階では、前段階の許可件数を基準に保証件数を積み上げる。
    static func allowedBlockCount(
        blocks: [ChatTranscriptBlock],
        requestedLimit: Int,
        defaultLimit: Int,
        minimumBlocks: Int
    ) -> Int {
        allowedBlockCount(weights: blocks.map(weight), requestedLimit: requestedLimit,
            defaultLimit: defaultLimit, minimumBlocks: minimumBlocks)
    }

    static func allowedBlockCount(weights: [Int], requestedLimit: Int,
                                  defaultLimit: Int, minimumBlocks: Int) -> Int {
        guard !weights.isEmpty, requestedLimit > 0 else { return 0 }

        let candidateCount = min(weights.count, requestedLimit)
        let normalizedDefaultLimit = max(1, defaultLimit)
        let scale = max(1, requestedLimit / normalizedDefaultLimit)
        // 最新ブロックは単体で予算を超えても必ず含める。minimumBlocks は reveal 由来の
        // 明示要求を渡す口としても使うため、実効下限は最低 1 件とする。
        let minimumStep = max(1, minimumBlocks)
        var allowedCount = 0

        // allowed(1) = max(bc(1), min(candidate(1), minimumStep))
        // allowed(k) = max(bc(k), min(candidate(k), allowed(k - 1) + minimumStep))
        //
        // 候補が残る間は各段階で最低 minimumStep 件増え、保証側が強制する増分は
        // それを超えない。さらに増える場合は拡大した予算に収まる bc(k) が決めるため、
        // 既定件数が大きいだけで次段階の件数が倍になることはない。
        // candidate(k)・bc(k)・allowed(k - 1) はいずれも非減少なので allowed(k) も
        // 単調非減少になる。scale == 1 では従来どおり
        // max(bc(1), min(candidate(1), minimumStep)) となり、既定窓の返り値を変えない。
        for stage in 1...scale {
            let stageCandidateCount = min(
                weights.count,
                saturatedProduct(normalizedDefaultLimit, stage)
            )
            let stageBudgetedCount = countWithinWeightBudget(
                weights.suffix(stageCandidateCount),
                budget: saturatedProduct(defaultUnits, stage)
            )
            let guaranteedCount = stage == 1
                ? min(stageCandidateCount, minimumStep)
                : min(stageCandidateCount, saturatedSum(allowedCount, minimumStep))
            allowedCount = max(stageBudgetedCount, guaranteedCount)
        }

        return min(candidateCount, allowedCount)
    }

    /// 1 ブロックの描画コスト重みを返す。すべてのブロックに最低骨格費を課す。
    static func weight(of block: ChatTranscriptBlock) -> Int {
        switch block {
        case .commandGroup:
            return otherBlockUnits

        case .statusCard(let card):
            // 重みは開いている作業の行の数に比例させる（手で開いた行は View の状態なので数えない）。
            return saturatedSum(
                saturatedSum(statusCardBaseUnits, saturatedProduct(card.rows.count, statusCardRowUnits)),
                saturatedProduct(card.openEntryCount, statusCardEntryUnits)
            )

        case .single(let item):
            switch item {
            case .agentMessage(_, let text, _),
                 .userMessage(_, let text, _, _, _),
                 .reasoning(_, let text, _):
                return max(otherBlockUnits, saturatedProduct(text.count, textCharacterUnits))

            case .error(_, let message, _):
                return max(otherBlockUnits, saturatedProduct(message.count, textCharacterUnits))

            case .fileChange(_, let changes, _, _):
                let totalLineCount = changes.reduce(into: 0) { count, change in
                    count = saturatedSum(count, ChatMessageRenderCache.diffLines(change.diff).count)
                }
                guard FileChangeDisplayPolicy.defaultExpanded(lineCount: totalLineCount) else {
                    return otherBlockUnits
                }
                let visibleLineCount = min(totalLineCount, FileChangeDisplayPolicy.visibleLineLimit)
                return max(otherBlockUnits, saturatedProduct(visibleLineCount, diffLineUnits))

            case .commandExecution,
                 .taskList,
                 .subAgentMarker,
                 .turnCost,
                 .userQuestion:
                return otherBlockUnits
            }
        }
    }

    static func weight(of block: SessionRuntimeChatReadBlock) -> Int {
        switch block.content {
        case .item(.inline(let item)): weight(of: .single(item))
        case .item(.deferred(let marker)):
            max(otherBlockUnits, marker.preview.text.count * textCharacterUnits)
        case .card(let card):
            // カードは全タスク行を描くので、行数で頭打ちにしない（ADR 0234）。
            saturatedSum(saturatedSum(statusCardBaseUnits, saturatedProduct(card.totalRowCount, statusCardRowUnits)),
                card.header.isLive ? 30 * statusCardEntryUnits : 0)
        case .commandGroup: otherBlockUnits
        }
    }

    private static func countWithinWeightBudget(_ weights: ArraySlice<Int>, budget: Int) -> Int {
        var used = 0
        var count = 0
        for weight in weights.reversed() {
            guard weight <= budget - used else { break }
            used += weight
            count += 1
        }
        return count
    }

    private static func saturatedProduct(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? Int.max : result.partialValue
    }

    static func countWithinBudget(
        _ blocks: ArraySlice<ChatTranscriptBlock>,
        budget: Int
    ) -> Int {
        var usedUnits = 0
        var count = 0

        for block in blocks.reversed() {
            let blockWeight = weight(of: block)
            guard blockWeight <= budget - usedUnits else { break }
            usedUnits += blockWeight
            count += 1
        }

        return count
    }

    private static func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }
}
