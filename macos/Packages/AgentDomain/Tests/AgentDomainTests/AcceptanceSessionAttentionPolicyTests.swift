// 契約の正本: tasks/task-2.md — 対応待ち状態が続く間は赤表示を維持する導出。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 背景: シングルビューでは表示中セッションの hasUnseenCompletion が即座に既読化されるため、
// 「未確認フラグ」だけを赤表示の根拠にすると質問・承認の保留中でも赤が消える。
// 契約: 入力を待つ状態（awaitingApproval / awaitingUserQuestion）の間は、既読化に関係なく
// requiresAttention == true。それ以外は従来どおり hasUnseenCompletion に従う。

import Foundation
import Testing
@testable import AgentDomain

@Suite("Acceptance: SessionAttentionPolicy（ask-question-ux task-2）")
struct AcceptanceSessionAttentionPolicyTests {
    @Test func 質問待ちは既読でも赤を維持する() {
        #expect(SessionAttentionPolicy.requiresAttention(
            status: .awaitingUserQuestion, hasUnseenCompletion: false
        ))
    }

    @Test func 承認待ちも既読でも赤を維持する() {
        #expect(SessionAttentionPolicy.requiresAttention(
            status: .awaitingApproval(prompt: "Approve?"), hasUnseenCompletion: false
        ))
    }

    @Test func 未確認フラグが立っていれば状態に依らず赤() {
        #expect(SessionAttentionPolicy.requiresAttention(status: .idle, hasUnseenCompletion: true))
        #expect(SessionAttentionPolicy.requiresAttention(status: .running, hasUnseenCompletion: true))
    }

    @Test func 通常状態かつ既読なら赤にしない() {
        #expect(!SessionAttentionPolicy.requiresAttention(status: .running, hasUnseenCompletion: false))
        #expect(!SessionAttentionPolicy.requiresAttention(status: .idle, hasUnseenCompletion: false))
        #expect(!SessionAttentionPolicy.requiresAttention(status: .starting, hasUnseenCompletion: false))
    }

    @Test func 完了とエラーは未確認フラグの従来挙動のまま() {
        #expect(!SessionAttentionPolicy.requiresAttention(
            status: .completed(exitCode: 0), hasUnseenCompletion: false
        ))
        #expect(!SessionAttentionPolicy.requiresAttention(
            status: .error(message: "boom"), hasUnseenCompletion: false
        ))
        #expect(SessionAttentionPolicy.requiresAttention(
            status: .error(message: "boom"), hasUnseenCompletion: true
        ))
    }
}
