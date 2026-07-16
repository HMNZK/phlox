import Testing
import Foundation
import SwiftTerm
@testable import TerminalUI

/// セッション再起動時の terminal リセット挙動の回帰テスト。
///
/// バグ: ワークスペース変更（restart）で旧 Claude Code が alternate screen buffer に入ったまま
/// kill され、`resetBuffer()` が alt buffer の中身を消すだけで normal buffer に戻していなかった。
/// その結果、再 spawn した新プロセスの `?1049h` が SwiftTerm の `activateAltBuffer` 早期 return
/// （既に alt なら何もしない）に当たり、画面が黒いまま戻らなかった。
@MainActor
struct TerminalCoordinatorResetTests {
    /// 旧プロセスが alt screen に入ったまま終わっても、`resetBuffer()` 後は normal buffer に戻り、
    /// 新プロセスの alt screen 再入が正しく再アクティブ化されることを検証する。
    @Test
    func resetBuffer_returnsToNormalBufferSoNextAltScreenReactivates() {
        let coordinator = TerminalCoordinator()
        let terminal = coordinator.terminalView.getTerminal()

        // 旧 TUI: alternate screen に入り "OLD" を描画した状態を再現。
        coordinator.feed(Data("\u{1b}[?1049h".utf8))
        coordinator.feed(Data("OLD".utf8))
        #expect(terminal.isCurrentBufferAlternate)
        #expect(terminal.getCharacter(col: 0, row: 0) == "O")

        // restart 前処理。修正前は alt buffer のまま残るのがバグ。修正後は normal buffer に戻る。
        coordinator.resetBuffer()
        #expect(terminal.isCurrentBufferAlternate == false)

        // 新 TUI が alt screen に入り直す。修正前は activateAltBuffer が早期 return し
        // viewport 充填・再描画がスキップされるが、修正後は normal→alt へ正しく再アクティブ化され、
        // 新しい描画内容が反映される。
        coordinator.feed(Data("\u{1b}[?1049h".utf8))
        coordinator.feed(Data("NEW".utf8))
        #expect(terminal.isCurrentBufferAlternate)
        #expect(terminal.getCharacter(col: 0, row: 0) == "N")
        #expect(terminal.getCharacter(col: 1, row: 0) == "E")
        #expect(terminal.getCharacter(col: 2, row: 0) == "W")
    }
}
