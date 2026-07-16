// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 監査所見: 認証トークン・env 辞書全体を平文 JSON (sessions.json) に永続化している。
// 採用方針（ゲート①承認・案A）: encode で token を出力しない。env は秘密系キーを除外して出力する。
// decode は後方互換（旧 JSON の token / env はそのまま読める）。
// 監査所見(nit): SessionTokenStore.register が空文字列トークンを受理する。
import Foundation
import Testing
@testable import AgentDomain

private func acceptanceSecretsDescriptor(
    env: [String: String],
    token: String?
) -> PersistedSessionDescriptor {
    PersistedSessionDescriptor(
        id: SessionID(rawValue: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!),
        kind: .claudeCode,
        workingDirectory: "/tmp/work",
        name: "Secrets",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        command: "/usr/local/bin/claude",
        args: [],
        env: env,
        token: token
    )
}

private func acceptanceEncodeToJSONObject(
    _ descriptor: PersistedSessionDescriptor
) throws -> [String: Any] {
    let data = try JSONEncoder().encode(descriptor)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

@Test func acceptance_encode_omitsTokenKey() throws {
    let descriptor = acceptanceSecretsDescriptor(env: [:], token: "super-secret-token-value")
    let data = try JSONEncoder().encode(descriptor)

    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["token"] == nil, "token は平文 JSON へ出力しない")

    let jsonString = try #require(String(data: data, encoding: .utf8))
    #expect(!jsonString.contains("super-secret-token-value"))
}

@Test func acceptance_encode_filtersSecretEnvKeysAndKeepsOperationalKeys() throws {
    let env: [String: String] = [
        // 除外されるべき秘密系（大文字小文字を問わない・接尾辞判定）
        "PHLOX_TOKEN": "secret-a",
        "Github_Token": "secret-b",
        "ANTHROPIC_API_KEY": "secret-c",
        "MY_SECRET": "secret-d",
        "DB_PASSWORD": "secret-e",
        "AWS_CREDENTIALS": "secret-f",
        // 保持されるべき運用系
        "PATH": "/usr/bin:/bin",
        "HOME": "/Users/someone",
        "PHLOX_API_URL": "http://127.0.0.1:1",
        "TERM": "xterm-256color",
    ]
    let descriptor = acceptanceSecretsDescriptor(env: env, token: nil)

    let object = try acceptanceEncodeToJSONObject(descriptor)
    let encodedEnv = try #require(object["env"] as? [String: String])

    #expect(encodedEnv.keys.sorted() == ["HOME", "PATH", "PHLOX_API_URL", "TERM"])

    let jsonString = try #require(String(
        data: try JSONEncoder().encode(descriptor), encoding: .utf8
    ))
    for secret in ["secret-a", "secret-b", "secret-c", "secret-d", "secret-e", "secret-f"] {
        #expect(!jsonString.contains(secret), "秘密値 \(secret) が JSON に漏れている")
    }
}

@Test func acceptance_decode_legacyTokenAndEnvRemainReadable() throws {
    // 旧バージョンが書いた sessions.json（token あり・env 無フィルタ）は読み続けられること。
    // 読み取り側の互換を保つことで、既存ファイルは次回保存時に自然にスクラブされる。
    let json = """
    {
      "id": { "rawValue": "55555555-5555-5555-5555-555555555555" },
      "kind": "claudeCode",
      "workingDirectory": "/tmp/work",
      "name": "Legacy",
      "projectID": null,
      "startedAt": 0,
      "command": "/usr/local/bin/claude",
      "args": [],
      "env": {"PHLOX_TOKEN": "legacy-env-token", "PATH": "/usr/bin"},
      "token": "legacy-token"
    }
    """

    let descriptor = try JSONDecoder().decode(
        PersistedSessionDescriptor.self,
        from: Data(json.utf8)
    )

    #expect(descriptor.token == "legacy-token")
    #expect(descriptor.env["PHLOX_TOKEN"] == "legacy-env-token")
    #expect(descriptor.env["PATH"] == "/usr/bin")
}

@Test func acceptance_roundTrip_dropsSecretsButPreservesOtherFields() throws {
    let descriptor = acceptanceSecretsDescriptor(
        env: ["PHLOX_TOKEN": "secret", "PATH": "/usr/bin"],
        token: "round-trip-token"
    )

    let data = try JSONEncoder().encode(descriptor)
    let decoded = try JSONDecoder().decode(PersistedSessionDescriptor.self, from: data)

    #expect(decoded.token == nil)
    #expect(decoded.env == ["PATH": "/usr/bin"])
    #expect(decoded.id == descriptor.id)
    #expect(decoded.workingDirectory == descriptor.workingDirectory)
    #expect(decoded.name == descriptor.name)
    #expect(decoded.command == descriptor.command)
    #expect(decoded.startedAt == descriptor.startedAt)
}

@Test func acceptance_sessionTokenStore_ignoresEmptyTokenRegistration() async {
    let store = SessionTokenStore()
    let session = SessionID()

    await store.register("", for: session)
    #expect(await store.session(forToken: "") == nil)
    #expect(await store.token(for: session) == nil)

    // 有効トークン登録後の空文字列 register は no-op（既存マッピングを壊さない）
    await store.register("valid-token", for: session)
    await store.register("", for: session)
    #expect(await store.token(for: session) == "valid-token")
    #expect(await store.session(forToken: "valid-token") == session)
}
