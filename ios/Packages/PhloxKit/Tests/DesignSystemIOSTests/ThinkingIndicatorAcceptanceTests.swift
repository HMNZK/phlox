import Testing
import Foundation
import SwiftUI
@testable import DesignSystemIOS

// task-1 受け入れテスト（PM 著・凍結）。契約: tasks/task-1.md
// DSThinkingAnimationModel の純関数位相計算と、DS 部品3点の存在・初期化可能性を検証する。

@Suite("DSThinkingAnimationModel 受け入れ（純関数位相計算）")
struct ThinkingAnimationModelAcceptanceTests {

    @Test("不透明度は全ドット・広範な時刻で 0.2...1.0 に収まる")
    func opacityStaysInRange() {
        for dot in 0..<DSThinkingAnimationModel.dotCount {
            for t in stride(from: -2.0, through: 6.0, by: 0.05) {
                let opacity = DSThinkingAnimationModel.opacity(dotIndex: dot, at: t)
                #expect(opacity >= 0.2, "dot=\(dot) t=\(t) opacity=\(opacity)")
                #expect(opacity <= 1.0, "dot=\(dot) t=\(t) opacity=\(opacity)")
            }
        }
    }

    @Test("period 経過後は同位相（周期性）")
    func opacityIsPeriodic() {
        let period = DSThinkingAnimationModel.period
        #expect(period > 0)
        for dot in 0..<DSThinkingAnimationModel.dotCount {
            for t in [0.0, 0.3, 0.7, 1.1] {
                let a = DSThinkingAnimationModel.opacity(dotIndex: dot, at: t)
                let b = DSThinkingAnimationModel.opacity(dotIndex: dot, at: t + period)
                #expect(abs(a - b) < 0.0001, "dot=\(dot) t=\(t)")
            }
        }
    }

    @Test("ドット同士は位相がずれている（全ドットが常に同値ではない）")
    func dotsAreStaggered() {
        #expect(DSThinkingAnimationModel.dotCount == 3)
        var foundDifference = false
        for t in stride(from: 0.0, through: DSThinkingAnimationModel.period, by: 0.02) {
            let values = (0..<DSThinkingAnimationModel.dotCount)
                .map { DSThinkingAnimationModel.opacity(dotIndex: $0, at: t) }
            if let first = values.first, values.contains(where: { abs($0 - first) > 0.05 }) {
                foundDifference = true
                break
            }
        }
        #expect(foundDifference, "全時刻で全ドットが同値＝位相ずれが実装されていない")
    }

    @Test("同一入力に対して決定的（乱数・現在時刻に依存しない）")
    func opacityIsDeterministic() {
        for dot in 0..<DSThinkingAnimationModel.dotCount {
            let a = DSThinkingAnimationModel.opacity(dotIndex: dot, at: 0.42)
            let b = DSThinkingAnimationModel.opacity(dotIndex: dot, at: 0.42)
            #expect(a == b)
        }
    }
}

@Suite("DS チャット活動部品 受け入れ（存在・初期化）")
@MainActor
struct ChatActivityComponentsAcceptanceTests {

    @Test("DSThinkingIndicator が reasoningPreview の有無どちらでも初期化できる")
    func thinkingIndicatorInitializes() {
        _ = DSThinkingIndicator()
        _ = DSThinkingIndicator(reasoningPreview: "実装方針を検討中")
    }

    @Test("DSSubAgentRow がテキストで初期化できる")
    func subAgentRowInitializes() {
        _ = DSSubAgentRow(text: "Sub-agent explore-map running: コードベース調査")
    }

    @Test("DSReasoningText がテキストで初期化できる")
    func reasoningTextInitializes() {
        _ = DSReasoningText(text: "ユーザーの意図はチャット UI のパリティ改善")
    }
}
