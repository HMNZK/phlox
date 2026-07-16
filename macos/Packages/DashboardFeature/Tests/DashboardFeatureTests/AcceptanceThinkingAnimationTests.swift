// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — Thinking アニメーションの位相計算（純関数）。
// 「安易な点滅ではないリッチな表現」を検証可能な性質（連続性・多階調・波位相差・周期性・有界）
// として符号化する。アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
@testable import SessionFeature

private let base = Date(timeIntervalSinceReferenceDate: 1_000)
private let dotCount = 3

/// 1周期を 60fps でサンプリングした全ドットの状態列。
private func sampledStates(index: Int) -> [ThinkingAnimationModel.DotState] {
    let steps = Int(ThinkingAnimationModel.period * 60)
    return (0..<steps).map { step in
        ThinkingAnimationModel.dotState(
            index: index,
            dotCount: dotCount,
            date: base.addingTimeInterval(Double(step) / 60)
        )
    }
}

@Test func thinking_determinism_sameInputSameOutput() {
    let a = ThinkingAnimationModel.dotState(index: 1, dotCount: dotCount, date: base)
    let b = ThinkingAnimationModel.dotState(index: 1, dotCount: dotCount, date: base)
    #expect(a == b)
}

@Test func thinking_periodicity_repeatsAfterOnePeriod() {
    let t = base.addingTimeInterval(0.4)
    let a = ThinkingAnimationModel.dotState(index: 0, dotCount: dotCount, date: t)
    let b = ThinkingAnimationModel.dotState(
        index: 0, dotCount: dotCount, date: t.addingTimeInterval(ThinkingAnimationModel.period))
    #expect(abs(a.opacity - b.opacity) < 1e-6)
    #expect(abs(a.scale - b.scale) < 1e-6)
    #expect(abs(a.yOffset - b.yOffset) < 1e-6)
}

@Test func thinking_continuity_noStepJumpsAt60fps() {
    // 点滅（二値のステップ変化）を排除する: 1フレーム（1/60s）での変化量が小さいこと。
    for index in 0..<dotCount {
        let states = sampledStates(index: index)
        for i in 1..<states.count {
            #expect(abs(states[i].opacity - states[i - 1].opacity) <= 0.25)
            #expect(abs(states[i].scale - states[i - 1].scale) <= 0.25)
            #expect(abs(states[i].yOffset - states[i - 1].yOffset) <= 1.5)
        }
    }
}

@Test func thinking_richness_opacityHasManyLevels() {
    // 二値点滅なら distinct は 2。滑らかな変調なら多階調になる。
    let states = sampledStates(index: 0)
    let distinct = Set(states.map { ($0.opacity * 100).rounded() })
    #expect(distinct.count >= 6)
}

@Test func thinking_richness_hasVisibleMotion() {
    // opacity 以外にも動き（縦の揺れ or 呼吸スケール）があること。
    let states = sampledStates(index: 0)
    let yAmplitude = states.map(\.yOffset).max()! - states.map(\.yOffset).min()!
    let scaleAmplitude = states.map(\.scale).max()! - states.map(\.scale).min()!
    #expect(yAmplitude > 0.5 || scaleAmplitude > 0.1)
}

@Test func thinking_wavePhase_adjacentDotsDiffer() {
    // 全ドット同時明滅（フラッシュ）ではなく、波として位相がずれていること。
    let t = base.addingTimeInterval(0.3)
    let a = ThinkingAnimationModel.dotState(index: 0, dotCount: dotCount, date: t)
    let b = ThinkingAnimationModel.dotState(index: 1, dotCount: dotCount, date: t)
    #expect(a != b)
}

@Test func thinking_bounds_staysWithinLayoutBudget() {
    // セル高を壊さない有界性（ADR 0046 の高さ契約を間接保護）。
    for index in 0..<dotCount {
        for s in sampledStates(index: index) {
            #expect(s.opacity >= 0.1 && s.opacity <= 1.0)
            #expect(s.scale >= 0.4 && s.scale <= 1.8)
            #expect(abs(s.yOffset) <= 6.0)
        }
    }
}
