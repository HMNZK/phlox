// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — シングルビューのヘッダ行をグリッド並みの縦幅に詰める。
// セッション名の表示自体は View 構成のためユニットテストでは固定せず、
// フェーズ4の ImageRenderer 目視とレビューで検証する（tasks/task-1.md 成功基準）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Testing
import CoreGraphics
@testable import SessionFeature

@Suite("Single view header layout acceptance (task-1)")
struct AcceptanceSingleHeaderLayoutTests {
    @Test func ヘッダ行の高さはグリッド相当の32ptに詰める() {
        // 旧: 64pt 固定（アイコンのみで余白過多）。グリッドのタイルヘッダ（アイコン24＋
        // padding(.vertical, 4)≈32pt）に合わせる。メイン/サブ両ペインが共有する定数なので
        // 罫線整列（Bug4）は保たれる。
        #expect(SubAgentSplitLayout.headerHeight == 32)
    }
}
