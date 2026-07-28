import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 端末の「1 文字が何桁を占めるか」と、それを実際の描画幅へ揃えるための字送り。
///
/// 端末は等幅の格子で、全角は 2 桁・半角は 1 桁を占める。ところが等幅システムフォントが
/// 等幅なのは**半角だけ**で、全角は CJK のフォールバックフォントが描く。実測すると
/// 「あ」は 1.49 桁、「（」は 0.75 桁しかなく、桁数どおりに並ばない。1 行に全角が 20 文字
/// あれば 10 桁ぶんずれる——これが表や罫線が崩れる正体（→ ADR 0038）。
///
/// そこで**文字ごとに字送り（kern）を足して、占めるべき桁数ちょうどの幅にする**。
/// 各文字が桁位置に釘付けになるので、ずれが積み上がらない。
///
/// 実測値はキャッシュする（1 画面に数百種類しか出てこない）。キャッシュを持つので
/// `@MainActor` に閉じている——描画からしか呼ばないため、これで足りる。
@MainActor
enum TerminalCellMetrics {

    /// この文字が端末で占める桁数。`wcwidth` と同じ判定を使う（端末側の格子と揃える）。
    static func columns(of character: Character) -> Int {
        if let cached = columnsCache[character] { return cached }
        let columns = measureColumns(of: character)
        columnsCache[character] = columns
        return columns
    }

    private static func measureColumns(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first, let utf8Locale else { return 1 }
        // `wcwidth` は locale が UTF-8 でないと非 ASCII を判定できず -1 を返す。プロセス全体の
        // locale を書き換えず、この呼び出しの間だけスレッドの locale を差し替える。
        let previous = uselocale(utf8Locale)
        defer { _ = uselocale(previous) }
        // 判定不能（-1）や結合文字（0）は 1 桁として扱う。0 桁にすると次の文字へ重なる。
        return wcwidth(wchar_t(scalar.value)) == 2 ? 2 : 1
    }

    /// 1 文字を桁数ちょうどの幅へ収めるための描き方。
    struct Layout: Hashable {
        /// フォントサイズの倍率。桁数より広い文字を縮めて収めるため 1 以下になることがある。
        var scale: CGFloat
        /// 縮めたうえで残る余白。文字の後ろへ足して次の文字を桁位置へ送る。
        var kerning: CGFloat
    }

    /// この文字を桁数ちょうどの幅にする倍率と字送り。
    ///
    /// 桁数より**狭い**文字（全角の多く）は字送りで送るだけでよい。桁数より**広い**文字
    /// （`⏺` は 1 桁の枠に 2.08 桁ぶん描かれる）は字送りが負になり次の文字へ重なるので、
    /// 縮めて枠に収める。端末も 1 セルの中に収めて描くので、そちらへ寄せる。
    static func layout(of character: Character, fontSize: CGFloat, cellWidth: CGFloat) -> Layout {
        let target = CGFloat(columns(of: character)) * cellWidth
        let advance = advance(of: character, fontSize: fontSize)
        guard advance > target, advance > 0 else {
            return Layout(scale: 1, kerning: target - advance)
        }
        return Layout(scale: target / advance, kerning: 0)
    }

    /// 実際に描かれる幅。文字種ごとにフォールバック先が違うので実測する（キャッシュ）。
    static func advance(of character: Character, fontSize: CGFloat) -> CGFloat {
        let key = AdvanceKey(character: character, fontSize: fontSize)
        if let cached = advanceCache[key] { return cached }
        let measured = measure(String(character), fontSize: fontSize)
        advanceCache[key] = measured
        return measured
    }

    private struct AdvanceKey: Hashable {
        let character: Character
        let fontSize: CGFloat
    }

    private static var advanceCache: [AdvanceKey: CGFloat] = [:]
    private static var columnsCache: [Character: Int] = [:]

    private static let utf8Locale: locale_t? = newlocale(LC_CTYPE_MASK, "en_US.UTF-8", nil)

    private static func measure(_ text: String, fontSize: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        #elseif canImport(AppKit)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        #else
        return fontSize
        #endif
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}
