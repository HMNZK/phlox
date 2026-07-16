import Testing
@testable import SessionFeature

@Suite("Theme reactive chat whitebox")
struct ThemeReactiveChatWhiteboxTests {

    @Test
    func highlightCacheKeySeparatesSameCodeByTheme() {
        let code = "let task3_theme_cache_probe = \"value\""
        let phlox = ChatMessageRenderCache.highlightCacheKey(code: code, themeID: "phlox")
        let githubLight = ChatMessageRenderCache.highlightCacheKey(code: code, themeID: "github-light")
        let phloxAgain = ChatMessageRenderCache.highlightCacheKey(code: code, themeID: "phlox")

        #expect(phlox != githubLight)
        #expect(phlox == phloxAgain)
        #expect(phlox.hasSuffix(code))
        #expect(githubLight.hasSuffix(code))
    }
}
