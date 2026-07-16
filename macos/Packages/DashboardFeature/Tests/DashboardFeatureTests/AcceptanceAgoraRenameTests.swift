// task-3 の不変受け入れテスト（PM 著・実装役は編集禁止）。
// 契約の正本: tasks/task-3.md — アゴラ討論参加者の役割ベース命名。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
@testable import DashboardFeature

@Suite("Acceptance: アゴラ参加者の役割ベース命名（task-3）")
struct AcceptanceAgoraRenameTests {
    @Test func 役割名がそのままセッション名になる() {
        let name = AgoraParticipantNaming.name(forRole: "UXデザイナー", existingNames: [])
        #expect(name == "UXデザイナー")
    }

    @Test func 既存名と衝突したら連番2を付与する() {
        let name = AgoraParticipantNaming.name(
            forRole: "UXデザイナー",
            existingNames: ["UXデザイナー", "Foxglove"]
        )
        #expect(name == "UXデザイナー 2")
    }

    @Test func 連番も埋まっていたら最小の空き連番を使う() {
        let name = AgoraParticipantNaming.name(
            forRole: "批判者",
            existingNames: ["批判者", "批判者 2", "批判者 3"]
        )
        #expect(name == "批判者 4")
    }

    @Test func 役割がnilならリネームしない() {
        let name = AgoraParticipantNaming.name(forRole: nil, existingNames: ["Foxglove"])
        #expect(name == nil)
    }

    @Test func 役割が空文字ならリネームしない() {
        let name = AgoraParticipantNaming.name(forRole: "", existingNames: [])
        #expect(name == nil)
    }

    @Test func 衝突しない役割名は既存名の集合に影響されない() {
        let name = AgoraParticipantNaming.name(
            forRole: "ファシリテーター",
            existingNames: ["UXデザイナー", "批判者", "Iris"]
        )
        #expect(name == "ファシリテーター")
    }
}
