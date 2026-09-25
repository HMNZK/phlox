// task-4 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-4.md — ブランチ picker の提示状態機械 ComposerBranchPickerModel。
// クラッシュ根絶の核心不変条件:「popover は最終内容が確定してから提示され、提示中に内容を変えない」
// （NSPopover の提示中アニメーションリサイズが表示サイクル再入 SIGSEGV を誘発するため。
//   lldb 実測スタック: PopoverHostingView.updateAnimatedWindowSize → NSMoveHelper _doAnimation
//   → UpdateCycle 再入 → EXC_BAD_ACCESS(0x0)）
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえで
// ハーネス部分に限り修理してよい。

import Foundation
import Testing
@testable import SessionFeature

private struct StubError: Error {}

@Suite struct AcceptanceBranchPickerPresentationTests {

    /// chip クリック（読み込み開始）の時点では提示しない（Loading 表示の popover を出さない）。
    @Test func beginOpenDoesNotPresentWhileLoading() {
        var model = ComposerBranchPickerModel()
        model.beginOpen()
        #expect(model.phase == .loading)
        #expect(model.isPresented == false)
    }

    /// 読み込み完了で初めて提示され、内容（一覧）は提示時点で確定している。
    @Test func presentationHappensOnlyAfterBranchesAreLoaded() {
        var model = ComposerBranchPickerModel()
        model.beginOpen()
        model.finishLoading(.success(["dev", "main"]))
        #expect(model.isPresented == true)
        #expect(model.branches == ["dev", "main"])
    }

    /// 提示中に届いた読み込み結果は無視する（提示中の内容差し替え＝リサイズを構造的に禁止）。
    @Test func staleLoadResultDoesNotMutateBranchesWhilePresented() {
        var model = ComposerBranchPickerModel()
        model.beginOpen()
        model.finishLoading(.success(["dev", "main"]))
        model.finishLoading(.success(["dev", "main", "feature/x"]))
        #expect(model.branches == ["dev", "main"], "提示中の一覧差し替えは popover リサイズを誘発するため禁止")
        #expect(model.isPresented == true)
    }

    /// ブランチを選んでも切り替えが済むまで閉じない。済んだら閉じる（B3・2026-09-25 ユーザー承認で変更。
    /// 箱は NSPopover ではなく SwiftUI の重ね表示になったので、提示中のリサイズによる落ちは起きない）。
    @Test func selectionClosesAfterTheCheckoutSucceeds() {
        var model = ComposerBranchPickerModel()
        model.beginOpen()
        model.finishLoading(.success(["dev", "main"]))
        model.select(branch: "main")
        #expect(model.isPresented == true)
        model.finishCheckout(.success(()), branch: "main")
        #expect(model.isPresented == false)
    }

    /// 切り替えに失敗したら開いたまま、一覧の中に理由を出す（PhloxReply O7）。
    @Test func checkoutFailureStaysOpenWithTheReason() {
        var model = ComposerBranchPickerModel()
        model.beginOpen()
        model.finishLoading(.success(["dev", "main"]))
        model.select(branch: "main")
        model.finishCheckout(.failure(StubError()), branch: "main")
        #expect(model.isPresented == true)
        #expect(model.branches == ["dev", "main"])
        #expect(model.checkoutErrorMessage != nil)
        model.dismiss()
        #expect(model.checkoutErrorMessage == nil)
    }

    /// 読み込み失敗は提示せず、エラーメッセージを保持する。
    @Test func loadFailurePresentsNothingAndKeepsError() {
        var model = ComposerBranchPickerModel()
        model.beginOpen()
        model.finishLoading(.failure(StubError()))
        #expect(model.isPresented == false)
        #expect(model.phase == .idle)
        #expect(model.errorMessage != nil)
    }

    /// 空一覧でも提示してよい（「No local branches」固定表示。以後内容は変わらない）。
    @Test func emptyBranchListStillPresentsWithStableContent() {
        var model = ComposerBranchPickerModel()
        model.beginOpen()
        model.finishLoading(.success([]))
        #expect(model.isPresented == true)
        #expect(model.branches.isEmpty)
    }

    /// 提示中・読み込み中は外部起因の chip 更新（30秒周期の refreshCurrentBranch）を延期する。
    /// 提示中に currentBranch が変わると checkmark 行の構成が変わり popover がリサイズされるため
    /// （stage2 レビュー指摘の残穴。ビューは本フラグで周期 refresh をゲートする）。
    @Test func externalRefreshIsDeferredWhileLoadingOrPresented() {
        var model = ComposerBranchPickerModel()
        #expect(model.allowsExternalRefresh == true)
        model.beginOpen()
        #expect(model.allowsExternalRefresh == false)
        model.finishLoading(.success(["dev"]))
        #expect(model.allowsExternalRefresh == false)
        model.dismiss()
        #expect(model.allowsExternalRefresh == true)
    }

    /// dismiss で idle に戻り、次回 beginOpen で新しい読み込みが有効になる。
    @Test func dismissReturnsToIdleAndAllowsFreshReload() {
        var model = ComposerBranchPickerModel()
        model.beginOpen()
        model.finishLoading(.success(["dev"]))
        model.dismiss()
        #expect(model.isPresented == false)
        model.beginOpen()
        model.finishLoading(.success(["dev", "main"]))
        #expect(model.branches == ["dev", "main"])
    }
}
