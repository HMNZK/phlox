// task-44（UX-01b）受け入れテスト。PersistedSessionDescriptor の名前四フィールドと互換。
//
// 実パス: macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDescriptorTests.swift
// ベースラインでの red 理由: `titleSource` / `flowerName` / `fullDerivedTitle` / `titleState` /
// `updating(titleState:)` は本タスクが追加する公開面で、baseline の descriptor には無い。
//
// 契約: tasks/task-44.md descriptor の後方互換・成功基準 1。
// 期待値は契約リテラル。被検査関数から生成しない。実装役はアサーションを変更禁止。

import Foundation
import Testing
@testable import AgentDomain

@Suite("task-44: PersistedSessionDescriptor title fields")
struct AcceptanceSessionTitleDescriptorTests {
    private let sessionID = SessionID(
        rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    )
    private let parentID = SessionID(
        rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    )
    private let projectID = ProjectID(
        rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    )

    private func expectState(
        _ state: SessionTitleState,
        _ name: String,
        _ source: SessionTitleSource,
        _ flowerName: String?,
        _ fullDerivedTitle: String?,
        _ label: String
    ) {
        #expect(state.name == name, Comment(rawValue: "\(label) name"))
        #expect(state.source == source, Comment(rawValue: "\(label) source"))
        #expect(state.flowerName == flowerName, Comment(rawValue: "\(label) flowerName"))
        #expect(state.fullDerivedTitle == fullDerivedTitle, Comment(rawValue: "\(label) fullDerivedTitle"))
        #expect(state.name == name, Comment(rawValue: "\(label) descriptor.name matches titleState"))
    }

    private func expectDescriptorState(
        _ descriptor: PersistedSessionDescriptor,
        _ name: String,
        _ source: SessionTitleSource,
        _ flowerName: String?,
        _ fullDerivedTitle: String?,
        _ label: String
    ) {
        #expect(descriptor.name == name, Comment(rawValue: "\(label) stored name"))
        expectState(descriptor.titleState, name, source, flowerName, fullDerivedTitle, label)
    }

    private func makeDescriptor(
        name: String,
        titleSource: SessionTitleSource? = nil,
        flowerName: String? = nil,
        fullDerivedTitle: String? = nil,
        backend: SessionBackend = .pty,
        token: String? = "secret-token",
        env: [String: String] = ["PATH": "/usr/bin", "PHLOX_TOKEN": "env-secret"],
        chatNativeSessionId: String? = "native-1",
        pid: pid_t? = 4242,
        role: String? = "批判者"
    ) -> PersistedSessionDescriptor {
        PersistedSessionDescriptor(
            id: sessionID,
            kind: .claudeCode,
            workingDirectory: "/tmp/work",
            name: name,
            projectID: projectID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            command: "/usr/local/bin/claude",
            args: ["--flag"],
            env: env,
            backend: backend,
            chatNativeSessionId: chatNativeSessionId,
            token: token,
            resumeID: "resume-1",
            parentSessionID: parentID,
            pid: pid,
            launchContext: .interactive,
            role: role,
            titleSource: titleSource,
            flowerName: flowerName,
            fullDerivedTitle: fullDerivedTitle
        )
    }

    private func makeDescriptorByAgentRef(
        name: String,
        titleSource: SessionTitleSource? = nil,
        flowerName: String? = nil,
        fullDerivedTitle: String? = nil
    ) -> PersistedSessionDescriptor {
        PersistedSessionDescriptor(
            id: sessionID,
            agentRef: .builtin(.claudeCode),
            workingDirectory: "/tmp/work",
            name: name,
            projectID: projectID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            command: "/usr/local/bin/claude",
            args: [],
            env: ["PATH": "/usr/bin"],
            titleSource: titleSource,
            flowerName: flowerName,
            fullDerivedTitle: fullDerivedTitle
        )
    }

    private func decodeJSON(_ json: String) throws -> PersistedSessionDescriptor {
        try JSONDecoder().decode(PersistedSessionDescriptor.self, from: Data(json.utf8))
    }

    private func encodeObject(_ descriptor: PersistedSessionDescriptor) throws -> [String: Any] {
        let data = try JSONEncoder().encode(descriptor)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func legacyJSON(
        name: String,
        titleSourceLine: String = "",
        flowerNameLine: String = "",
        fullDerivedTitleLine: String = ""
    ) -> String {
        """
        {
          "id": { "rawValue": "11111111-1111-1111-1111-111111111111" },
          "kind": "claudeCode",
          "workingDirectory": "/tmp/work",
          "name": \(jsonString(name)),
          "projectID": null,
          "startedAt": 0,
          "command": "/usr/local/bin/claude",
          "args": [],
          "env": {},
          "token": "token",
          "resumeID": null
          \(titleSourceLine)
          \(flowerNameLine)
          \(fullDerivedTitleLine)
        }
        """
    }

    private func jsonString(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - 両 initializer と同じ正規化

    @Test("kind initializer の generated 相当は flower 正規化を通す")
    func kindInitializerNormalizesFlower() {
        let descriptor = makeDescriptor(
            name: "Rose",
            titleSource: .flower,
            flowerName: " Rose ",
            fullDerivedTitle: nil
        )
        expectDescriptorState(descriptor, "Rose", .flower, "Rose", nil, "kind flower")
    }

    @Test("agentRef initializer も同じ正規化を通す")
    func agentRefInitializerNormalizesFlower() {
        let descriptor = makeDescriptorByAgentRef(
            name: "Rose",
            titleSource: .flower,
            flowerName: " Rose ",
            fullDerivedTitle: nil
        )
        expectDescriptorState(descriptor, "Rose", .flower, "Rose", nil, "agentRef flower")
    }

    @Test("不整合 derived は両 initializer で manual へ退避し name を置換しない")
    func bothInitializersRetreatInconsistentDerived() {
        let kindInit = makeDescriptor(
            name: "修正",
            titleSource: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "別件"
        )
        let refInit = makeDescriptorByAgentRef(
            name: "修正",
            titleSource: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "別件"
        )
        expectDescriptorState(kindInit, "修正", .manual, "Rose", nil, "kind derived mismatch")
        expectDescriptorState(refInit, "修正", .manual, "Rose", nil, "agentRef derived mismatch")
    }

    @Test("不整合 flower は name を残して manual へ退避する")
    func initializerRetreatsInconsistentFlower() {
        let descriptor = makeDescriptor(
            name: "Lily",
            titleSource: .flower,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        expectDescriptorState(descriptor, "Lily", .manual, "Rose", nil, "flower mismatch")
    }

    @Test("valid derived は name / fullDerivedTitle を正規化済み単一行として保持する")
    func initializerKeepsValidDerived() {
        let descriptor = makeDescriptor(
            name: "修正",
            titleSource: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "修正"
        )
        expectDescriptorState(descriptor, "修正", .derived, "Rose", "修正", "valid derived")
    }

    @Test("titleSource nil は legacy。保存 name を手動名として保持し花名・導出全文は nil")
    func nilTitleSourceIsLegacy() {
        let descriptor = makeDescriptor(
            name: "Rose",
            titleSource: nil,
            flowerName: "推測花",
            fullDerivedTitle: "旧候補"
        )
        expectDescriptorState(descriptor, "Rose", .manual, nil, nil, "nil source legacy")
    }

    // MARK: - JSON 往復

    @Test("JSON 往復で flower 正規化結果が同じ")
    func jsonRoundTripFlower() throws {
        let original = makeDescriptor(
            name: "Rose",
            titleSource: .flower,
            flowerName: " Rose ",
            fullDerivedTitle: nil
        )
        let decoded = try JSONDecoder().decode(
            PersistedSessionDescriptor.self,
            from: try JSONEncoder().encode(original)
        )
        expectDescriptorState(decoded, "Rose", .flower, "Rose", nil, "round-trip flower")
        #expect(decoded.backend == original.backend)
        #expect(decoded.chatNativeSessionId == original.chatNativeSessionId)
    }

    @Test("JSON 往復で derived 正規化結果が同じ")
    func jsonRoundTripDerived() throws {
        let original = makeDescriptor(
            name: "修正",
            titleSource: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "修正"
        )
        let decoded = try JSONDecoder().decode(
            PersistedSessionDescriptor.self,
            from: try JSONEncoder().encode(original)
        )
        expectDescriptorState(decoded, "修正", .derived, "Rose", "修正", "round-trip derived")
    }

    @Test("JSON 往復で手動名・空名を保持する")
    func jsonRoundTripManualAndEmpty() throws {
        let manual = makeDescriptor(
            name: " 手動\n名 ",
            titleSource: .manual,
            flowerName: "Rose",
            fullDerivedTitle: "旧候補"
        )
        let empty = makeDescriptor(
            name: "",
            titleSource: .manual,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        let decodedManual = try JSONDecoder().decode(
            PersistedSessionDescriptor.self,
            from: try JSONEncoder().encode(manual)
        )
        let decodedEmpty = try JSONDecoder().decode(
            PersistedSessionDescriptor.self,
            from: try JSONEncoder().encode(empty)
        )
        expectDescriptorState(decodedManual, " 手動\n名 ", .manual, "Rose", nil, "round-trip manual")
        expectDescriptorState(decodedEmpty, "", .manual, "Rose", nil, "round-trip empty")
    }

    @Test("旧 JSON の Rose は source 不在の legacy 手動名")
    func oldJSONRoseIsLegacyManual() throws {
        let descriptor = try decodeJSON(legacyJSON(name: "Rose"))
        expectDescriptorState(descriptor, "Rose", .manual, nil, nil, "old Rose")
        #expect(descriptor.token == "token")
    }

    @Test("旧 JSON の通常名は legacy 手動名")
    func oldJSONNormalNameIsLegacyManual() throws {
        let descriptor = try decodeJSON(legacyJSON(name: "作業中"))
        expectDescriptorState(descriptor, "作業中", .manual, nil, nil, "old normal")
    }

    @Test("旧 JSON の空名は空の手動名のまま。短縮 ID に置換しない")
    func oldJSONEmptyNameStaysEmptyManual() throws {
        let descriptor = try decodeJSON(legacyJSON(name: ""))
        expectDescriptorState(descriptor, "", .manual, nil, nil, "old empty")
    }

    @Test("titleSource 不在は legacy")
    func missingTitleSourceIsLegacy() throws {
        let descriptor = try decodeJSON(legacyJSON(name: "Rose"))
        expectDescriptorState(descriptor, "Rose", .manual, nil, nil, "missing source")
    }

    @Test("titleSource null は legacy")
    func nullTitleSourceIsLegacy() throws {
        let descriptor = try decodeJSON(
            legacyJSON(name: "Rose", titleSourceLine: ",\"titleSource\": null")
        )
        expectDescriptorState(descriptor, "Rose", .manual, nil, nil, "null source")
    }

    @Test("未知 titleSource でも descriptor 全体を破棄せず手動名と正規化花名を残す")
    func unknownTitleSourceKeepsManualAndFlower() throws {
        let descriptor = try decodeJSON(
            legacyJSON(
                name: "作業中",
                titleSourceLine: ",\"titleSource\": \"future-source\"",
                flowerNameLine: ",\"flowerName\": \" Rose \"",
                fullDerivedTitleLine: ",\"fullDerivedTitle\": \"旧候補\""
            )
        )
        expectDescriptorState(descriptor, "作業中", .manual, "Rose", nil, "unknown source")
    }

    @Test("不整合 derived の decode は手動へ退避する")
    func decodeInconsistentDerivedRetreatsToManual() throws {
        let descriptor = try decodeJSON(
            legacyJSON(
                name: "修正",
                titleSourceLine: ",\"titleSource\": \"derived\"",
                flowerNameLine: ",\"flowerName\": \"Rose\"",
                fullDerivedTitleLine: ",\"fullDerivedTitle\": \"別件\""
            )
        )
        expectDescriptorState(descriptor, "修正", .manual, "Rose", nil, "decode derived mismatch")
    }

    @Test("不整合 flower の decode は手動へ退避する")
    func decodeInconsistentFlowerRetreatsToManual() throws {
        let descriptor = try decodeJSON(
            legacyJSON(
                name: "Lily",
                titleSourceLine: ",\"titleSource\": \"flower\"",
                flowerNameLine: ",\"flowerName\": \"Rose\""
            )
        )
        expectDescriptorState(descriptor, "Lily", .manual, "Rose", nil, "decode flower mismatch")
    }

    // MARK: - updating

    @Test("updating(titleState:) は四フィールドを一体更新する")
    func updatingTitleStateReplacesFourFields() {
        let original = makeDescriptor(
            name: "Rose",
            titleSource: .flower,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        let next = original.updating(
            titleState: SessionTitleState(
                name: "修正",
                source: .derived,
                flowerName: "Rose",
                fullDerivedTitle: "修正"
            )
        )
        expectDescriptorState(next, "修正", .derived, "Rose", "修正", "updating titleState")
        #expect(next.id == original.id)
        #expect(next.pid == original.pid)
        #expect(next.backend == original.backend)
        #expect(next.chatNativeSessionId == original.chatNativeSessionId)
    }

    @Test("updating(name:) は手動変更。source を derived のまま残さない")
    func updatingNameBecomesManual() {
        let derived = makeDescriptor(
            name: "修正",
            titleSource: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "修正"
        )
        let renamed = derived.updating(name: "通知を修正")
        expectDescriptorState(renamed, "通知を修正", .manual, "Rose", nil, "updating name")
    }

    @Test("updating(pid:) は名前四フィールドを保持する")
    func updatingPidKeepsTitleFields() {
        let original = makeDescriptor(
            name: "修正",
            titleSource: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "修正"
        )
        let updated = original.updating(pid: 9999)
        #expect(updated.pid == 9999)
        expectDescriptorState(updated, "修正", .derived, "Rose", "修正", "updating pid")
    }

    @Test("updating(role:) は名前四フィールドを保持する")
    func updatingRoleKeepsTitleFields() {
        let original = makeDescriptor(
            name: "Rose",
            titleSource: .flower,
            flowerName: "Rose"
        )
        let updated = original.updating(role: "ファシリテーター")
        #expect(updated.role == "ファシリテーター")
        expectDescriptorState(updated, "Rose", .flower, "Rose", nil, "updating role")
    }

    @Test("updating(chatNativeSessionId:) は名前四フィールドを保持する")
    func updatingNativeSessionIDKeepsTitleFields() {
        let original = makeDescriptor(
            name: "修正",
            titleSource: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "修正",
            chatNativeSessionId: "native-old"
        )
        let updated = original.updating(chatNativeSessionId: "native-new")
        #expect(updated.chatNativeSessionId == "native-new")
        expectDescriptorState(updated, "修正", .derived, "Rose", "修正", "updating native")
    }

    // MARK: - 秘密情報・互換

    @Test("encode は token を出力しない")
    func encodeOmitsToken() throws {
        let descriptor = makeDescriptor(
            name: "Rose",
            titleSource: .flower,
            flowerName: "Rose",
            token: "super-secret-token-value"
        )
        let object = try encodeObject(descriptor)
        #expect(object["token"] == nil)
        let encoded = try JSONEncoder().encode(descriptor)
        let jsonString = try #require(String(data: encoded, encoding: .utf8))
        #expect(!jsonString.contains("super-secret-token-value"))
    }

    @Test("encode は秘密 env を除去し運用キーと backend / native session ID を残す")
    func encodeScrubsSecretsAndKeepsCompatibilityFields() throws {
        let descriptor = makeDescriptor(
            name: "Rose",
            titleSource: .flower,
            flowerName: "Rose",
            backend: .appServer,
            env: [
                "PHLOX_TOKEN": "secret-a",
                "PATH": "/usr/bin",
                "TERM": "xterm-256color",
            ],
            chatNativeSessionId: "native-keep"
        )
        let object = try encodeObject(descriptor)
        let encodedEnv = try #require(object["env"] as? [String: String])
        #expect(encodedEnv.keys.sorted() == ["PATH", "TERM"])
        #expect(object["backend"] as? String == "appServer")
        #expect(object["chatNativeSessionId"] as? String == "native-keep")
        let encoded = try JSONEncoder().encode(descriptor)
        let jsonString = try #require(String(data: encoded, encoding: .utf8))
        #expect(!jsonString.contains("secret-a"))
    }
}
