// task-35（UI-06）の受け入れテスト。
//
// ベースラインでの red 理由: `ThemePreviewModel` と
// `ThemePreviewModel.make(theme:)`、`ThemePreviewModel.Layer` は
// 本タスクが新設を要求する API で、baseline_commit には存在しない
// （参照未解決でコンパイル不能＝red）。
//
// 契約: 新しいテーマや配色規則は追加せず、候補テーマの既存 RGB から
// アプリ外観の見本とターミナル配色の色帯を決める。数値は AppTheme の
// 実値であり、スクリーンショットの測色値ではない。

import DesignSystem
import Testing

@Suite("task-35: theme preview model")
struct AcceptanceThemePreviewModelTests {
    @Test("Phlox の背景・主文字・選択行・入力面・枠を字面で固定する")
    func phloxLayerRGBAndOpacityAreFrozen() {
        let model = ThemePreviewModel.make(theme: .phlox)

        #expect(model.background == RGB(17, 17, 17))
        #expect(model.textPrimary == RGB(230, 230, 230))
        #expect(model.selectedRow.rgb == RGB(230, 230, 230))
        #expect(model.selectedRow.opacity == 0.10)
        #expect(model.inputFill.rgb == RGB(255, 255, 255))
        #expect(model.inputFill.opacity == 0.04)
        #expect(model.inputBorder.rgb == RGB(255, 255, 255))
        #expect(model.inputBorder.opacity == 0.06)
    }

    @Test("Phlox の色帯 8 色と順序を字面で固定する")
    func phloxTerminalSwatchesAreFrozen() {
        let model = ThemePreviewModel.make(theme: .phlox)

        #expect(model.terminalSwatches == [
            RGB(14, 14, 14),
            RGB(239, 68, 68),
            RGB(52, 211, 153),
            RGB(251, 191, 36),
            RGB(96, 165, 250),
            RGB(217, 119, 87),
            RGB(56, 189, 248),
            RGB(214, 214, 214),
        ])
    }

    @Test("GitHub Light の背景は白、inputBorder は opacity 0.86 で RGB は同テーマの textPrimary")
    func githubLightBackgroundAndInputBorder() {
        let theme = AppTheme.githubLight
        let model = ThemePreviewModel.make(theme: theme)

        #expect(model.background == RGB(255, 255, 255))
        #expect(model.inputBorder.opacity == 0.86)
        #expect(model.inputBorder.rgb == theme.textPrimary)
        #expect(model.themeID == "github-light")
        #expect(model.themeName == "GitHub Light")
    }

    @Test("文言 5 種、themeID/name、マーカー色を固定する")
    func labelsIdentityAndMarker() {
        let phlox = ThemePreviewModel.make(theme: .phlox)
        #expect(phlox.appLabel == "アプリ外観")
        #expect(phlox.terminalLabel == "ターミナル配色")
        #expect(phlox.bodyText == "本文の見本")
        #expect(phlox.selectedRowText == "現在の会話")
        #expect(phlox.inputText == "メッセージを入力")
        #expect(phlox.themeID == "phlox")
        #expect(phlox.themeName == "Phlox")
        #expect(phlox.currentMarker == RGB(217, 119, 87))

        let github = ThemePreviewModel.make(theme: .githubLight)
        #expect(github.appLabel == "アプリ外観")
        #expect(github.terminalLabel == "ターミナル配色")
        #expect(github.bodyText == "本文の見本")
        #expect(github.selectedRowText == "現在の会話")
        #expect(github.inputText == "メッセージを入力")
        #expect(github.currentMarker == AppTheme.githubLight.accent)
    }

    @Test("登録 10 テーマの ID・名前・順序を固定し、候補由来の背景・文字・選択行・枠・色帯へ写像する")
    func tenRegisteredThemesMapFromCandidate() {
        #expect(ThemeStore.all.map(\.id) == [
            "phlox", "tokyo-night", "dracula", "catppuccin-mocha", "gruvbox-dark", "nord",
            "catppuccin-latte", "solarized-light", "github-light", "phlox-light",
        ])
        #expect(ThemeStore.all.map(\.name) == [
            "Phlox", "Tokyo Night", "Dracula", "Catppuccin Mocha", "Gruvbox Dark", "Nord",
            "Catppuccin Latte", "Solarized Light", "GitHub Light", "Phlox Light",
        ])
        #expect(ThemeStore.all.count == 10)

        for theme in ThemeStore.all {
            #expect(theme.ansi.count == 16, "\(theme.id) ANSI は 16 色")

            let model = ThemePreviewModel.make(theme: theme)
            #expect(model.themeID == theme.id)
            #expect(model.themeName == theme.name)
            #expect(model.background == theme.background)
            #expect(model.textPrimary == theme.textPrimary)
            #expect(model.currentMarker == theme.accent)
            #expect(model.selectedRow.rgb == theme.textPrimary)
            #expect(model.selectedRow.opacity == 0.10)
            #expect(model.inputFill.rgb == RGB(255, 255, 255))
            #expect(model.inputFill.opacity == 0.04)
            #expect(model.appLabel == "アプリ外観")
            #expect(model.terminalLabel == "ターミナル配色")
            #expect(model.bodyText == "本文の見本")
            #expect(model.selectedRowText == "現在の会話")
            #expect(model.inputText == "メッセージを入力")

            if Self.lightThemeIDs.contains(theme.id) {
                #expect(model.inputBorder.rgb == theme.textPrimary, "\(theme.id) 明色枠 RGB")
                #expect(model.inputBorder.opacity == 0.86, "\(theme.id) 明色枠 opacity")
            } else {
                #expect(model.inputBorder.rgb == RGB(255, 255, 255), "\(theme.id) 暗色枠 RGB")
                #expect(model.inputBorder.opacity == 0.06, "\(theme.id) 暗色枠 opacity")
            }

            #expect(model.terminalSwatches.count == 8, "\(theme.id) 色帯は 8 色")
            #expect(model.terminalSwatches[0] == theme.terminalBackground)
            #expect(Array(model.terminalSwatches[1...6]) == Array(theme.ansi[1...6]))
            #expect(model.terminalSwatches[7] == theme.terminalForeground)
        }
    }

    @Test("Phlox → GitHub Light → Phlox の呼び出しで前の候補が混入しない")
    func successiveMakesDoNotLeakPreviousCandidate() {
        let first = ThemePreviewModel.make(theme: .phlox)
        let second = ThemePreviewModel.make(theme: .githubLight)
        let third = ThemePreviewModel.make(theme: .phlox)

        #expect(first.themeID == "phlox")
        #expect(first.background == RGB(17, 17, 17))
        #expect(first.textPrimary == RGB(230, 230, 230))
        #expect(first.inputBorder.opacity == 0.06)
        #expect(first.terminalSwatches[0] == RGB(14, 14, 14))

        #expect(second.themeID == "github-light")
        #expect(second.background == RGB(255, 255, 255))
        #expect(second.inputBorder.opacity == 0.86)
        #expect(second.inputBorder.rgb == AppTheme.githubLight.textPrimary)
        #expect(second.terminalSwatches[0] == RGB(255, 255, 255))
        #expect(second.background != first.background)
        #expect(second.themeID != first.themeID)

        #expect(third.themeID == "phlox")
        #expect(third.background == RGB(17, 17, 17))
        #expect(third.textPrimary == RGB(230, 230, 230))
        #expect(third.selectedRow.rgb == RGB(230, 230, 230))
        #expect(third.inputBorder.rgb == RGB(255, 255, 255))
        #expect(third.inputBorder.opacity == 0.06)
        #expect(third.terminalSwatches == first.terminalSwatches)
        #expect(third.themeID != second.themeID)
        #expect(third.background != second.background)
    }

    @Test("ThemePreviewModel と Layer は Equatable & Sendable")
    func modelIsEquatableAndSendable() {
        requireEquatable(ThemePreviewModel.self)
        requireEquatable(ThemePreviewModel.Layer.self)
    }

    /// AppTheme.swift の bg 実値から、相対輝度 0.5 以上になる明色 4 テーマ。
    private static let lightThemeIDs: Set<String> = [
        "catppuccin-latte", "solarized-light", "github-light", "phlox-light",
    ]
}

private func requireEquatable<T: Equatable & Sendable>(_: T.Type) {}
