// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — 役割の永続化（descriptor round-trip）と役割プロンプト生成。
// spawn --role の CLI/ControlServer 配線は実装役の白箱テスト＋レビュー＋フェーズ4で担保する。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

// MARK: - fixtures

private func descriptor(role: String? = nil) -> PersistedSessionDescriptor {
    PersistedSessionDescriptor(
        id: SessionID(),
        kind: .claudeCode,
        workingDirectory: "/tmp/proj",
        name: "Daisy",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 1_000_000),
        command: "claude",
        args: [],
        env: [:],
        role: role
    )
}

@Suite("Agora role persistence & prompt acceptance (task-3)")
struct AcceptanceAgoraRoleTests {

    // MARK: - descriptor の役割永続化

    @Test func role_は_encode_decode_round_trip_で保存復元される() throws {
        let original = descriptor(role: "批判者")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedSessionDescriptor.self, from: data)
        #expect(decoded.role == "批判者")
    }

    @Test func role_なし_旧descriptor_は_nil_で復元される後方互換() throws {
        let original = descriptor(role: nil)
        let data = try JSONEncoder().encode(original)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("\"role\""))  // nil は JSON にキー自体を出さない（旧形式と同一）
        let decoded = try JSONDecoder().decode(PersistedSessionDescriptor.self, from: data)
        #expect(decoded.role == nil)
    }

    @Test func updating_role_は_role_だけを変えた複製を返す() {
        let original = descriptor(role: nil)
        let updated = original.updating(role: "推進者")
        #expect(updated.role == "推進者")
        #expect(updated.id == original.id)
        #expect(updated.name == original.name)
        #expect(original.role == nil)  // 元は不変
    }

    // MARK: - 役割プロンプト生成

    @Test func 参加者プロンプトは役割_議題_PASS規約_帰属形式_上限を含む() {
        let config = AgoraDiscussionConfig(maxUtterances: 24, maxAgents: 4)
        let prompt = AgoraRolePromptTemplate.prompt(
            role: "批判者",
            agenda: "キャッシュ戦略の是非",
            isFacilitator: false,
            config: config
        )
        #expect(prompt.contains("批判者"))
        #expect(prompt.contains("キャッシュ戦略の是非"))
        #expect(prompt.contains("PASS"))
        #expect(prompt.contains("[from"))
        #expect(prompt.contains("24"))
        #expect(prompt.contains("4"))
        #expect(!prompt.contains("spawn --role"))  // 招集はファシリテーター専用の責務
    }

    @Test func ファシリテータープロンプトは招集手段と収束_最終まとめの責務を含む() {
        let config = AgoraDiscussionConfig()
        let prompt = AgoraRolePromptTemplate.prompt(
            role: "ファシリテーター",
            agenda: "議題Y",
            isFacilitator: true,
            config: config
        )
        #expect(prompt.contains("spawn --role"))
        #expect(prompt.contains("議題Y"))
        #expect(prompt.contains("まとめ"))
    }

    @Test func role_が_nil_でも議題とPASS規約を含むプロンプトを返す() {
        let prompt = AgoraRolePromptTemplate.prompt(
            role: nil,
            agenda: "議題Z",
            isFacilitator: false,
            config: AgoraDiscussionConfig()
        )
        #expect(prompt.contains("議題Z"))
        #expect(prompt.contains("PASS"))
        #expect(!prompt.isEmpty)
    }
}
