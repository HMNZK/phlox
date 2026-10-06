import Foundation
import Testing
@testable import CodexAppServerKit

@Test func intValueReturnsNilForOverflowAndNaNAndKeepsValidIntegers() {
    // `Int(value)` は 1e300 / NaN / ∞ で fatal error（プロセス abort）になる。
    // `Int(exactly:)` は表現不能な値を nil にし、正常整数は従来値を返す。
    #expect(JSONValue.number(1e300).intValue == nil)
    #expect(JSONValue.number(Double.nan).intValue == nil)
    #expect(JSONValue.number(Double.infinity).intValue == nil)
    #expect(JSONValue.number(-Double.infinity).intValue == nil)

    // 正常整数はそのまま。
    #expect(JSONValue.number(42).intValue == 42)
    #expect(JSONValue.number(0).intValue == 0)
    #expect(JSONValue.number(-7).intValue == -7)
    // 2^53 は Double で厳密に表現でき Int にも収まる大整数。従来値を返す。
    #expect(JSONValue.number(9_007_199_254_740_992).intValue == 9_007_199_254_740_992)

    // Double(Int.max) は丸めで 2^63（Int.max+1）になり Int に収まらない → nil が正しい。
    #expect(JSONValue.number(Double(Int.max)).intValue == nil)

    // 小数部を持つ値は整数として扱わない（exactly: の意味）。
    #expect(JSONValue.number(42.5).intValue == nil)

    // 数値以外は従来どおり nil。
    #expect(JSONValue.string("42").intValue == nil)
    #expect(JSONValue.null.intValue == nil)
}
