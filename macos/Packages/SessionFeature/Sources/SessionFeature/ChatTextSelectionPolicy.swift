import Foundation
import SwiftUI

/// チャット系ビューのテキスト選択可否を決める単一の場所。
///
/// SwiftUI の `.textSelection(.enabled)` は環境値として伝播し、**伝播先の `Text` 1 個ごとに**
/// 選択可能な表現を構築する。実測（run: single-view-switch-perf, 2026-07-29）では 1 個あたり
/// 約 1.8ms かかり、セッション切替 1 回 2447ms のうち 1987ms（81%）がこれだった。
/// 親へ 1 回だけ当てても伝播先で同じコストが出るため（親適用条件で 2443ms＝現行と同値）、
/// 「どこに当てるか」ではなく「どの範囲を選択可能にするか」を方針として持つ必要がある。
///
/// 方針: **1 ブロックあたりの `Text` 個数に上限があるかどうか**で分ける。
/// - `prose`（本文・コード・コマンド出力など）: 1 ブロックあたり数個で収まる。選択可能のまま。
///   実測でこの範囲の選択コストは合計 93ms で、無効化する理由がない。
/// - `diffLines`（file change の diff 1 行ごと）: 1 ブロックで最大 500 行まで増える唯一の箇所。
///   ここだけ個数の上限が無く、選択コストが青天井に積み上がる。行単位の選択は無効化し、
///   代わりにセクション単位のコピー手段（`FileChangeCell` のコピーボタン）で代替する。
enum ChatTextSelectionPolicy {
    /// 本文・コードなど、1 ブロックあたりの Text 個数が構造的に有界な箇所。
    static let prose = true

    /// diff 1 行ごとの選択。個数が有界でないため無効。
    /// 失う「diff の一部を選んでコピーする」手段は、file section ごとのコピーボタンで代替する。
    static let diffLines = false
}

extension View {
    /// チャット本文・コード・コマンド出力のテキスト選択。
    @ViewBuilder
    func chatTextSelection() -> some View {
        if ChatTextSelectionPolicy.prose {
            textSelection(.enabled)
        } else {
            textSelection(.disabled)
        }
    }

    /// file change の diff 1 行のテキスト選択。既定で無効（理由は `ChatTextSelectionPolicy`）。
    @ViewBuilder
    func diffLineTextSelection() -> some View {
        if ChatTextSelectionPolicy.diffLines {
            textSelection(.enabled)
        } else {
            textSelection(.disabled)
        }
    }
}
