import Foundation

/// 入力欄（ChatComposer）でハイライトすべき範囲の種別（task-2 契約面）。
enum ComposerHighlightKind: Equatable, Sendable {
    case slashCommand
    case fileReference
    /// claude CLI がキーワード型機能として拾う語（ultrathink / ultraplan / ultrareview / ultracode）。
    case keyword
}

/// ハイライト範囲（UTF16 オフセット）と種別。
struct ComposerHighlightSpan: Equatable, Sendable {
    let range: Range<Int>
    let kind: ComposerHighlightKind
}

/// 入力テキストからハイライト範囲を導出する純関数（task-2 契約面）。
/// シグネチャは受け入れテスト AcceptanceComposerHighlightTests が凍結している（変更禁止）。
/// 契約:
///   - 空白区切りトークンのうち "/" で始まるものを各1件 `.slashCommand`（"/" ＋ 空白以外の連続文字）。
///     トークン先頭の位置は問わない。トークン途中の "/" は対象外。
///   - 空白区切りトークンのうち "@" で始まるものを各1件 `.fileReference`（"@" ＋ 空白以外の連続文字）。
///   - range は UTF16 オフセット。CJK/絵文字でも正しいこと。決定論。
enum ComposerHighlight {
    static func spans(in text: String) -> [ComposerHighlightSpan] {
        var spans: [ComposerHighlightSpan] = []
        var tokenStart = text.startIndex

        while tokenStart < text.endIndex {
            while tokenStart < text.endIndex, text[tokenStart].isWhitespace {
                tokenStart = text.index(after: tokenStart)
            }
            guard tokenStart < text.endIndex else { break }

            let tokenEnd = text[tokenStart...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            let range = tokenStart.utf16Offset(in: text)..<tokenEnd.utf16Offset(in: text)

            if text[tokenStart] == "/" {
                spans.append(ComposerHighlightSpan(range: range, kind: .slashCommand))
            } else if text[tokenStart] == "@" {
                spans.append(ComposerHighlightSpan(range: range, kind: .fileReference))
            }

            tokenStart = tokenEnd
        }

        return spans
    }

    /// `spans(in:)` の結果に、claude CLI と同じ規則で検出した `.keyword` を加えて返す（task-1 契約面）。
    /// 契約:
    ///   - `includingKeywords: false` は `spans(in:)` と完全に同一の結果。
    ///   - `.keyword` のうち `.slashCommand` / `.fileReference` と1文字でも重なるものは落とす
    ///     （入力欄は1文字につき1色しか塗れないため、トークン種別の強調を優先する）。
    ///   - 返り値は `range.lowerBound` の昇順。range は UTF16 オフセット。決定論・副作用なし。
    static func spans(in text: String, includingKeywords: Bool) -> [ComposerHighlightSpan] {
        let tokenSpans = spans(in: text)
        guard includingKeywords else { return tokenSpans }

        let keywords = keywordSpans(in: text).filter { keyword in
            !tokenSpans.contains { $0.range.overlaps(keyword.range) }
        }
        guard !keywords.isEmpty else { return tokenSpans }

        return mergedByLowerBound(tokenSpans, keywords)
    }
}

// MARK: - キーワード検出（claude CLI v2.1.220 の実装を写す。実測日 2026-07-28）

private extension ComposerHighlight {

    /// CLI が検出する4語。CLI 追随の更新はここだけを直せば済むよう1箇所にまとめる。
    enum Keyword {
        /// 除外規則を持たない語。CLI 側実装 `wqr(e) = e.matchAll(/\bultrathink\b/gi)` に対応（規則X）。
        static let unrestricted = ["ultrathink"].map { Array($0.utf16) }
        /// 除外規則つきの語。CLI 側実装 `Rqs(e, t)` に対応（規則Y）。
        static let restricted = ["ultraplan", "ultrareview", "ultracode"].map { Array($0.utf16) }
    }

    /// 判定に使う ASCII の UTF16 コードユニット。数値リテラルの打ち間違いを避けるため文字から導出する。
    enum Unit {
        static let slash = UInt16(UInt8(ascii: "/"))
        static let backslash = UInt16(UInt8(ascii: "\\"))
        static let hyphen = UInt16(UInt8(ascii: "-"))
        static let question = UInt16(UInt8(ascii: "?"))
        static let dot = UInt16(UInt8(ascii: "."))
        static let underscore = UInt16(UInt8(ascii: "_"))
        static let backtick = UInt16(UInt8(ascii: "`"))
        static let doubleQuote = UInt16(UInt8(ascii: "\""))
        static let apostrophe = UInt16(UInt8(ascii: "'"))
        static let openBrace = UInt16(UInt8(ascii: "{"))
        static let closeBrace = UInt16(UInt8(ascii: "}"))
        static let openBracket = UInt16(UInt8(ascii: "["))
        static let closeBracket = UInt16(UInt8(ascii: "]"))
        static let openParen = UInt16(UInt8(ascii: "("))
        static let closeParen = UInt16(UInt8(ascii: ")"))
        static let lessThan = UInt16(UInt8(ascii: "<"))
        static let greaterThan = UInt16(UInt8(ascii: ">"))

        static let digits = UInt16(UInt8(ascii: "0"))...UInt16(UInt8(ascii: "9"))
        static let uppercase = UInt16(UInt8(ascii: "A"))...UInt16(UInt8(ascii: "Z"))
        static let lowercase = UInt16(UInt8(ascii: "a"))...UInt16(UInt8(ascii: "z"))
        static let caseOffset = UInt16(UInt8(ascii: "a") - UInt8(ascii: "A"))
    }

    /// 4語の出現範囲を UTF16 オフセットの昇順で返す。
    /// 走査は UTF16 コードユニット単位で行う。Character 単位だと絵文字・結合文字でオフセットがずれ、
    /// JS の string index（UTF16）とも既存 span 契約とも合わなくなる。
    static func keywordSpans(in text: String) -> [ComposerHighlightSpan] {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return [] }

        // 規則Y-1: 入力が "/" で始まるなら規則Yの語は1件も検出しない（規則X の ultrathink は検出する）。
        let allowsRestricted = units[0] != Unit.slash
        let regions = allowsRestricted ? protectedRegions(in: units) : []

        var result: [ComposerHighlightSpan] = []
        // 保護区間は昇順・非重複に収集され、マッチも開始位置の昇順に見つかるので、
        // カーソルを前進させるだけで内外を判定できる（毎回の全走査を避け O(n) に保つ）。
        var regionCursor = 0
        var index = 0

        while index < units.count {
            if let length = matchLength(of: Keyword.unrestricted, at: index, in: units) {
                result.append(ComposerHighlightSpan(range: index..<(index + length), kind: .keyword))
                index += length
                continue
            }

            if allowsRestricted, let length = matchLength(of: Keyword.restricted, at: index, in: units) {
                let end = index + length
                while regionCursor < regions.count, regions[regionCursor].upperBound <= index {
                    regionCursor += 1
                }
                let isProtected = regionCursor < regions.count && regions[regionCursor].contains(index)

                if !isProtected, !isExcludedByNeighbors(start: index, end: end, in: units) {
                    result.append(ComposerHighlightSpan(range: index..<end, kind: .keyword))
                }
                index = end
                continue
            }

            index += 1
        }

        return result
    }

    /// `candidates` のいずれかが `index` から ASCII 語境界つきで一致するなら、その UTF16 長を返す。
    /// 語境界は JS の `\b`（`\w` = `[A-Za-z0-9_]`）と同じ ASCII 判定にする。
    /// NSRegularExpression の `\b` は Unicode 語境界なので、そのまま使うと「日本語ultrathink」が
    /// JS では一致するのに Swift では一致せず、CLI の発火と表示がずれる。
    static func matchLength(of candidates: [[UInt16]], at index: Int, in units: [UInt16]) -> Int? {
        // 候補語はいずれも ASCII 語構成文字で始まり・終わるので、前後が語構成文字でないことが境界条件。
        if index > 0, isASCIIWordUnit(units[index - 1]) { return nil }

        for candidate in candidates {
            let end = index + candidate.count
            guard end <= units.count else { continue }
            if end < units.count, isASCIIWordUnit(units[end]) { continue }

            var matched = true
            for offset in 0..<candidate.count where asciiLowercased(units[index + offset]) != candidate[offset] {
                matched = false
                break
            }
            if matched { return candidate.count }
        }

        return nil
    }

    /// 規則Y-3〜5: 前後の文字による除外。
    static func isExcludedByNeighbors(start: Int, end: Int, in units: [UInt16]) -> Bool {
        if start > 0 {
            let previous = units[start - 1]
            if previous == Unit.slash || previous == Unit.backslash || previous == Unit.hyphen {
                return true
            }
        }

        guard end < units.count else { return false }
        let next = units[end]
        if next == Unit.slash || next == Unit.backslash || next == Unit.hyphen || next == Unit.question {
            return true
        }
        // "ultracode.md"・"ultracode.example.com" のようなファイル名/ドメインを避ける。
        // 直後が "." でもその次が語構成文字でなければ（"ultracode. 次へ"）除外しない。
        return next == Unit.dot && end + 1 < units.count && isUnicodeWordUnit(units[end + 1])
    }

    /// 規則Y-2: 保護区間を左から1回走査して収集する。
    /// 入れ子は扱わず、開いている種別が閉じるまで他の開始文字は無視する。
    /// 返す区間は「開始文字の位置」から「終了文字の次の位置」まで。昇順・非重複。
    /// 閉じないまま終端に達した区間は生成しない（終了文字が無い＝区間が確定しないため）。
    static func protectedRegions(in units: [UInt16]) -> [Range<Int>] {
        var regions: [Range<Int>] = []
        var openingUnit: UInt16?
        var expectedClosing: UInt16 = 0
        var start = 0

        for index in units.indices {
            let unit = units[index]

            guard let opening = openingUnit else {
                if let closing = closingUnit(forOpeningAt: index, in: units) {
                    openingUnit = unit
                    expectedClosing = closing
                    start = index
                }
                continue
            }

            // "[" が開いている間にさらに "[" が来たら開始位置を更新する。
            if opening == Unit.openBracket, unit == Unit.openBracket {
                start = index
                continue
            }
            guard unit == expectedClosing else { continue }
            // "'" は終了文字の次が語構成文字なら閉じない（"'don't ultracode'" を1区間として扱うため）。
            if opening == Unit.apostrophe,
               index + 1 < units.count,
               isUnicodeWordUnit(units[index + 1]) {
                continue
            }

            regions.append(start..<(index + 1))
            openingUnit = nil
        }

        return regions
    }

    /// `index` の文字が保護区間の開始条件を満たすなら、対応する終了文字を返す。
    static func closingUnit(forOpeningAt index: Int, in units: [UInt16]) -> UInt16? {
        switch units[index] {
        case Unit.backtick: return Unit.backtick
        case Unit.doubleQuote: return Unit.doubleQuote
        case Unit.openBrace: return Unit.closeBrace
        case Unit.openBracket: return Unit.closeBracket
        case Unit.openParen: return Unit.closeParen
        case Unit.lessThan:
            // "<" は次が [a-zA-Z/] のときだけ開く（"1 < 2" を保護区間にしない）。
            guard index + 1 < units.count, isTagLeadingUnit(units[index + 1]) else { return nil }
            return Unit.greaterThan
        case Unit.apostrophe:
            // "'" は直前が語構成文字なら開かない（"don't" の "'" で開かないようにする）。
            guard index == 0 || !isUnicodeWordUnit(units[index - 1]) else { return nil }
            return Unit.apostrophe
        default:
            return nil
        }
    }

    static func asciiLowercased(_ unit: UInt16) -> UInt16 {
        Unit.uppercase.contains(unit) ? unit &+ Unit.caseOffset : unit
    }

    /// JS の `\w`（= `[A-Za-z0-9_]`）。語境界の判定に使う。
    static func isASCIIWordUnit(_ unit: UInt16) -> Bool {
        Unit.digits.contains(unit)
            || Unit.uppercase.contains(unit)
            || Unit.lowercase.contains(unit)
            || unit == Unit.underscore
    }

    /// "<" が保護区間を開く条件（次の文字が `[a-zA-Z/]`）。
    static func isTagLeadingUnit(_ unit: UInt16) -> Bool {
        Unit.uppercase.contains(unit) || Unit.lowercase.contains(unit) || unit == Unit.slash
    }

    /// JS の `[\p{L}\p{N}_]`（ASCII 限定ではない）。保護区間の "'" 条件と "." 除外に使う。
    /// 単独サロゲート（対を成さない UTF16 片）は非該当。JS が1コードユニットを検査するのに揃える。
    static func isUnicodeWordUnit(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        if scalar == "_" { return true }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// 昇順の2列を開始オフセットの昇順に併合する。同点は第1引数を先に置き、決定論を保つ。
    static func mergedByLowerBound(
        _ primary: [ComposerHighlightSpan],
        _ secondary: [ComposerHighlightSpan]
    ) -> [ComposerHighlightSpan] {
        var merged: [ComposerHighlightSpan] = []
        merged.reserveCapacity(primary.count + secondary.count)
        var primaryIndex = 0
        var secondaryIndex = 0

        while primaryIndex < primary.count, secondaryIndex < secondary.count {
            if primary[primaryIndex].range.lowerBound <= secondary[secondaryIndex].range.lowerBound {
                merged.append(primary[primaryIndex])
                primaryIndex += 1
            } else {
                merged.append(secondary[secondaryIndex])
                secondaryIndex += 1
            }
        }
        merged.append(contentsOf: primary[primaryIndex...])
        merged.append(contentsOf: secondary[secondaryIndex...])

        return merged
    }
}
