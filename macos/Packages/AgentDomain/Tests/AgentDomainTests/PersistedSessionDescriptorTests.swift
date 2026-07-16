import Foundation
import Testing
@testable import AgentDomain

@Test func persistedSessionDescriptor_decodesOldJSONWithoutParentSessionID() throws {
    let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let json = """
    {
      "id": { "rawValue": "\(id.uuidString)" },
      "kind": "claudeCode",
      "workingDirectory": "/tmp/work",
      "name": "Root",
      "projectID": null,
      "startedAt": 0,
      "command": "/usr/local/bin/claude",
      "args": [],
      "env": {},
      "token": "token",
      "resumeID": null
    }
    """

    let descriptor = try JSONDecoder().decode(
        PersistedSessionDescriptor.self,
        from: Data(json.utf8)
    )

    #expect(descriptor.id == SessionID(rawValue: id))
    #expect(descriptor.backend == .pty)
    #expect(descriptor.codexThreadId == nil)
    #expect(descriptor.appServerUserAgent == nil)
    #expect(descriptor.codexSettings == nil)
    #expect(descriptor.parentSessionID == nil)
}

/// 全フィールドに区別可能な固定値を入れた descriptor(updating の保持検証用)。
/// 同じ引数で呼べば同一値になるため、期待値の組み立てにも使う。
private func makeFullDescriptor(
    name: String = "Original",
    resumeID: String? = "resume-original",
    backend: SessionBackend = .appServer,
    codexThreadId: String? = "thread-original",
    chatNativeSessionId: String? = nil,
    appServerUserAgent: String? = "codex-test/1",
    codexSettings: CodexAppServerSessionSettings? = CodexAppServerSessionSettings(
        selectedModel: "gpt-5-codex",
        selectedEffort: "medium",
        selectedPermissionProfile: ":workspace",
        isPlanMode: true
    ),
    pid: pid_t? = 1234,
    parentSessionID: SessionID
) -> PersistedSessionDescriptor {
    PersistedSessionDescriptor(
        id: SessionID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
        kind: .codex,
        workingDirectory: "/tmp/work",
        name: name,
        projectID: ProjectID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        command: "/usr/local/bin/codex",
        args: ["--flag", "value"],
        env: ["PATH": "/usr/bin"],
        backend: backend,
        codexThreadId: codexThreadId,
        chatNativeSessionId: chatNativeSessionId,
        appServerUserAgent: appServerUserAgent,
        codexSettings: codexSettings,
        token: nil,
        resumeID: resumeID,
        parentSessionID: parentSessionID,
        pid: pid
    )
}

@Test func persistedSessionDescriptor_updatingName_changesNameAndPreservesAllOtherFields() {
    let parent = SessionID()
    let descriptor = makeFullDescriptor(parentSessionID: parent)

    let updated = descriptor.updating(name: "Renamed")

    // Equatable 比較で name の更新と残り全フィールドの保持を一括検証する。
    #expect(updated == makeFullDescriptor(name: "Renamed", parentSessionID: parent))
}

@Test func persistedSessionDescriptor_updatingResumeID_changesResumeIDAndPreservesAllOtherFields() {
    let parent = SessionID()
    let descriptor = makeFullDescriptor(parentSessionID: parent)

    let updated = descriptor.updating(resumeID: "resume-new")

    #expect(updated == makeFullDescriptor(resumeID: "resume-new", parentSessionID: parent))
}

@Test func persistedSessionDescriptor_updatingChatNativeSessionID_changesChatNativeIDWithoutChangingResumeID() {
    let parent = SessionID()
    let descriptor = makeFullDescriptor(
        resumeID: "cursor-create-chat-id",
        chatNativeSessionId: "cursor-native-old",
        parentSessionID: parent
    )

    let updated = descriptor.updating(chatNativeSessionId: "cursor-native-new")

    #expect(updated == makeFullDescriptor(
        resumeID: "cursor-create-chat-id",
        chatNativeSessionId: "cursor-native-new",
        parentSessionID: parent
    ))
}

@Test func persistedSessionDescriptor_updatingParentSessionID_changesParentAndPreservesAllOtherFields() {
    let oldParent = SessionID()
    let newParent = SessionID()
    let descriptor = makeFullDescriptor(parentSessionID: oldParent)

    let updated = descriptor.updating(parentSessionID: newParent)

    #expect(updated == makeFullDescriptor(parentSessionID: newParent))
}

@Test func persistedSessionDescriptor_updatingCodexThread_changesThreadFieldsAndPreservesAllOtherFields() {
    let parent = SessionID()
    let descriptor = makeFullDescriptor(parentSessionID: parent)

    let updated = descriptor.updating(codexThreadId: "thread-new", appServerUserAgent: "codex-test/2")

    #expect(updated == makeFullDescriptor(
        codexThreadId: "thread-new",
        appServerUserAgent: "codex-test/2",
        parentSessionID: parent
    ))
}

@Test func persistedSessionDescriptor_updatingCodexSettings_changesSettingsAndPreservesAllOtherFields() {
    let parent = SessionID()
    let descriptor = makeFullDescriptor(parentSessionID: parent)
    let settings = CodexAppServerSessionSettings(
        selectedModel: "o4-mini",
        selectedEffort: "low",
        selectedPermissionProfile: ":read-only",
        isPlanMode: false
    )

    let updated = descriptor.updating(codexSettings: settings)

    #expect(updated == makeFullDescriptor(codexSettings: settings, parentSessionID: parent))
}

@Test func persistedSessionDescriptor_encodesAndDecodesCodexSettings() throws {
    let parent = SessionID()
    let descriptor = makeFullDescriptor(parentSessionID: parent)

    let data = try JSONEncoder().encode(descriptor)
    let decoded = try JSONDecoder().decode(PersistedSessionDescriptor.self, from: data)

    #expect(decoded == descriptor)
    #expect(decoded.codexSettings?.selectedModel == "gpt-5-codex")
    #expect(decoded.codexSettings?.isPlanMode == true)
}

// MARK: - pid（task-3: OS プロセス pid の永続化）

@Test func persistedSessionDescriptor_defaultsPidToNilWhenNotProvided() {
    let descriptor = PersistedSessionDescriptor(
        id: SessionID(),
        kind: .claudeCode,
        workingDirectory: "/tmp/work",
        name: "Root",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 0),
        command: "/usr/local/bin/claude",
        args: [],
        env: [:]
    )

    #expect(descriptor.pid == nil)
}

@Test func persistedSessionDescriptor_roundTripsPidWhenPresent() throws {
    let descriptor = PersistedSessionDescriptor(
        id: SessionID(rawValue: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!),
        kind: .claudeCode,
        workingDirectory: "/tmp/work",
        name: "Root",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        command: "/usr/local/bin/claude",
        args: [],
        env: [:],
        token: nil,
        pid: 4242
    )

    let data = try JSONEncoder().encode(descriptor)
    let decoded = try JSONDecoder().decode(PersistedSessionDescriptor.self, from: data)

    #expect(decoded == descriptor)
    #expect(decoded.pid == 4242)
}

@Test func persistedSessionDescriptor_decodesOldJSONWithoutPidAsNil() throws {
    let id = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    let json = """
    {
      "id": { "rawValue": "\(id.uuidString)" },
      "kind": "claudeCode",
      "workingDirectory": "/tmp/work",
      "name": "Root",
      "projectID": null,
      "startedAt": 0,
      "command": "/usr/local/bin/claude",
      "args": [],
      "env": {},
      "token": "token",
      "resumeID": null
    }
    """

    let descriptor = try JSONDecoder().decode(
        PersistedSessionDescriptor.self,
        from: Data(json.utf8)
    )

    #expect(descriptor.pid == nil)
}

@Test func persistedSessionDescriptor_decodesOldJSONWithoutLaunchContextAsInteractive() throws {
    let id = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    let json = """
    {
      "id": { "rawValue": "\(id.uuidString)" },
      "kind": "claudeCode",
      "workingDirectory": "/tmp/work",
      "name": "Root",
      "projectID": null,
      "startedAt": 0,
      "command": "/usr/local/bin/claude",
      "args": [],
      "env": {},
      "token": "token",
      "resumeID": null
    }
    """

    let descriptor = try JSONDecoder().decode(
        PersistedSessionDescriptor.self,
        from: Data(json.utf8)
    )

    #expect(descriptor.launchContext == .interactive)
}

@Test func persistedSessionDescriptor_updatingPid_changesPidAndPreservesAllOtherFields() {
    let parent = SessionID()
    let descriptor = makeFullDescriptor(parentSessionID: parent)

    let updated = descriptor.updating(pid: 9001)

    #expect(updated == makeFullDescriptor(pid: 9001, parentSessionID: parent))
    #expect(updated.pid == 9001)
}
