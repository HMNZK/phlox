import Testing
import SwiftUI
@testable import DesignSystemIOS

/// task-6 受け入れテスト（PM 著・実装役は編集禁止）。
/// ライトモードの「ナビバーだけダーク」ハリボテ根治: ナビバー chrome の配色をテーマ id 連動にする。
/// SwiftUI 側（.toolbarColorScheme 等）と UIKit appearance 双方がこの純関数を使うことで、
/// テーマ切替（AppRoot の .id remount）でナビバーも即ライト/ダークへ切り替わる。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
@MainActor
struct Wave2ChromeAcceptanceTests {

    @Test("ナビバー chrome の配色はテーマ id 連動（phlox-light→light / phlox→dark）")
    func barColorSchemeFollowsThemeID() {
        #expect(DSNavigationChrome.barColorScheme(for: "phlox-light") == .light)
        #expect(DSNavigationChrome.barColorScheme(for: "phlox") == .dark)
    }

    @Test("未知テーマ id は既定（dark）にフォールバックする")
    func barColorSchemeUnknownFallsBackToDark() {
        #expect(DSNavigationChrome.barColorScheme(for: "unknown-theme-xyz") == .dark)
    }
}
