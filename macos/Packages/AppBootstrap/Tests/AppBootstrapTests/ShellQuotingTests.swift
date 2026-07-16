import Foundation
import Testing
@testable import AppBootstrap

@Suite struct ShellQuotingTests {
    @Test func plainStringIsWrappedInSingleQuotes() {
        #expect(ShellQuoting.singleQuoted("abc") == "'abc'")
    }

    @Test func emptyStringBecomesEmptyQuotes() {
        #expect(ShellQuoting.singleQuoted("") == "''")
    }

    @Test func embeddedSingleQuoteIsEscaped() {
        #expect(ShellQuoting.singleQuoted("a'b") == "'a'\\''b'")
    }

    @Test func multipleSingleQuotesAreAllEscaped() {
        #expect(ShellQuoting.singleQuoted("'x'") == "''\\''x'\\'''")
    }

    @Test func shellMetacharactersAreLeftLiteral() {
        // $ や ` や " はシングルクォート内では展開されないため、そのまま包むだけでよい。
        #expect(ShellQuoting.singleQuoted("$HOME `id` \"q\"") == "'$HOME `id` \"q\"'")
    }

    @Test func pathWithSpacesIsQuotedAsSingleWord() {
        #expect(
            ShellQuoting.singleQuoted("/Users/o'brien/My Files/wrapper.sh")
                == "'/Users/o'\\''brien/My Files/wrapper.sh'"
        )
    }
}
