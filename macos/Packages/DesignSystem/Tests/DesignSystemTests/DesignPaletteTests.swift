import AgentDomain
import Testing
@testable import DesignSystem

/// 再設計（design_handoff_phlox_ui / 12 Design System）のトークン契約。
/// 既定 2 テーマは確定値そのもの、10 テーマすべてで文字 4.5:1・状態の記号 3:1 を保つ。
@Suite struct DesignPaletteTests {
    private func contrast(_ a: RGB, _ b: RGB) -> Double { DesignPalette.contrast(a, b) }

    private func faces(_ p: DesignPalette) -> [RGB] { [p.window, p.sidebar, p.card, p.panel, p.toolbar] }

    @Test("既定テーマは README の確定値を持つ")
    func defaultThemesUseDesignValues() {
        let light = AppTheme.phloxLight.palette
        #expect(light.window == RGB(0xFF, 0xFF, 0xFF))
        #expect(light.sidebar == RGB(0xF2, 0xF2, 0xF4))
        #expect(light.tabBar == RGB(0xEC, 0xEC, 0xEF))
        #expect(light.stalled.mark == RGB(0x94, 0x57, 0xDB))
        #expect(light.accentFill == RGB(0xB4, 0x55, 0x2F))
        let dark = AppTheme.phlox.palette
        #expect(dark.window == RGB(0x1E, 0x1E, 0x20))
        #expect(dark.popover == RGB(0x2F, 0x2F, 0x33))
        #expect(dark.approval.ink == RGB(0xF4, 0xBD, 0x68))
        #expect(AppTheme.phlox.background == dark.window)
        #expect(AppTheme.phlox.textPrimary == RGB(0xF2, 0xF2, 0xF4))
        #expect(AppTheme.phloxLight.textPrimary == RGB(0x1D, 0x1D, 0x1F))
        #expect(AppTheme.phlox.preferredColorScheme == .dark)
        #expect(AppTheme.phloxLight.preferredColorScheme == .light)
    }

    @Test("全テーマ: 状態の文言・accent の文字・差分は主要な面で 4.5:1 以上")
    func inkIsReadableEverywhere() {
        for theme in ThemeStore.all {
            let p = theme.palette
            let inks = [p.approval.ink, p.question.ink, p.error.ink, p.stalled.ink, p.accentInk, p.diffAdded, p.diffRemoved]
            for ink in inks {
                for face in faces(p) {
                    #expect(contrast(ink, face) >= 4.5, "\(theme.id): \(ink) on \(face) = \(contrast(ink, face))")
                }
            }
        }
    }

    /// 例外: Phlox Light の承認待ちの記号 #E39A2D は確定値だが白地で 2.35:1（デザイン側の食い違い。報告済み）。
    /// 文言（#8A5300）が状態を伝えるため、記号は補助表示として確定値のまま扱う。
    static let markExceptions: Set<String> = ["phlox-light/approval"]

    @Test("全テーマ: 状態の記号・縁はウィンドウ面で 3:1 以上（確定値の例外を除く）")
    func marksAreVisible() {
        for theme in ThemeStore.all {
            let p = theme.palette
            for (name, c) in [("approval", p.approval), ("question", p.question), ("error", p.error), ("stalled", p.stalled)] {
                guard !Self.markExceptions.contains("\(theme.id)/\(name)") else { continue }
                #expect(contrast(c.mark, p.window) >= 3.0, "\(theme.id) \(name): \(contrast(c.mark, p.window))")
            }
        }
    }

    @Test("全テーマ: 本文・補助・弱い文字は新しい面でも 4.5:1 以上")
    func textIsReadableOnNewFaces() {
        // 既定 2 テーマの弱い文字はモックの確定値（#8E8E94 / #75757B）で、4.5:1 を満たさない（2026-09-24 ユーザー決定）。
        for theme in ThemeStore.all {
            let texts = [AppTheme.phlox.id, AppTheme.phloxLight.id].contains(theme.id)
                ? [theme.textPrimary, theme.textSecondary] : [theme.textPrimary, theme.textSecondary, theme.textTertiary]
            for text in texts {
                for face in faces(theme.palette) {
                    #expect(contrast(text, face) >= 4.5, "\(theme.id): \(text) on \(face) = \(contrast(text, face))")
                }
            }
        }
    }

    @Test("主ボタンの白文字は accent の面で 4.5:1 以上")
    func accentFillCarriesWhiteText() {
        #expect(contrast(RGB(255, 255, 255), DesignPalette.accentFillColor) >= 4.5)
    }

    @Test("幅の範囲はクランプされる")
    func widthRangesClamp() {
        #expect(DSLayout.sidebarWidth.clamped(100) == 220)
        #expect(DSLayout.sidebarWidth.clamped(500) == 360)
        #expect(DSLayout.inspectorWidth.ideal == 280)
    }
}

/// 一覧の状態（`SessionDisplayState`）の決め方と語彙。
@Suite @MainActor struct SessionDisplayStateTests {
    @Test("SessionStatus に未読と無応答を重ねて決める")
    func resolve() {
        #expect(SessionDisplayState.resolve(.idle) == .idle)
        #expect(SessionDisplayState.resolve(.idle, hasUnseenCompletion: true) == .doneUnread)
        #expect(SessionDisplayState.resolve(.running) == .running)
        #expect(SessionDisplayState.resolve(.running, isStalled: true) == .stalled)
        #expect(SessionDisplayState.resolve(.awaitingApproval(prompt: "x"), isStalled: true) == .approval)
        #expect(SessionDisplayState.resolve(.awaitingUserQuestion) == .question)
        #expect(SessionDisplayState.resolve(.completed(exitCode: 0)) == .done)
        #expect(SessionDisplayState.resolve(.error(message: "e")) == .error)
    }

    @Test("対応待ちは 4 状態だけで、完了の未読は含めない")
    func attentionKinds() {
        #expect(SessionDisplayState.approval.attentionKind == .approval)
        #expect(SessionDisplayState.question.attentionKind == .question)
        #expect(SessionDisplayState.error.attentionKind == .error)
        #expect(SessionDisplayState.stalled.attentionKind == .stalled)
        for s in [SessionDisplayState.starting, .idle, .running, .doneUnread, .done] {
            #expect(s.attentionKind == nil)
        }
    }

    @Test("語彙は 12 Design System の表どおりで、使わない言葉を含まない")
    func vocabulary() {
        let all: [SessionDisplayState] = [.starting, .idle, .running, .approval, .question, .doneUnread, .done, .error, .stalled]
        #expect(all.map(\.label) == ["起動中", "待機", "実行中", "承認待ち", "質問待ち", "完了", "完了", "エラー", "無応答"])
        for s in all {
            let l = s.label
            #expect(!["入力待ち", "停止", "却下", "ハング"].contains(l))
        }
        #expect(SessionDisplayState.stalled.englishLabel == "unresponsive")
    }

    @Test("実行中件数の文言は日本語化する")
    func runningCountLabel() {
        #expect(RunningCountBadge.label(count: 2, nested: 0, japanese: true) == "2 実行中")
        #expect(RunningCountBadge.label(count: 2, nested: 1, japanese: false) == "2 running (1 internal)")
    }
}
