import Foundation
import Testing
@testable import AgentDomain

private func temporaryAgentsJSONURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "AgentDomainTests-agents-\(UUID().uuidString).json")
}

private func removeFile(at url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove test file \(url.path): \(error)")
    }
}

@Test func persistedSessionDescriptor_decodesLegacyBareAgentKindAsBuiltinRef() throws {
    let json = """
    {
      "id": {"rawValue": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"},
      "kind": "codex",
      "workingDirectory": "/tmp/phlox-codex",
      "name": "Legacy Codex",
      "projectID": null,
      "startedAt": 1800000000,
      "command": "/usr/local/bin/codex",
      "args": ["resume"],
      "env": {"PATH": "/usr/bin"}
    }
    """

    let descriptor = try JSONDecoder().decode(PersistedSessionDescriptor.self, from: Data(json.utf8))

    #expect(descriptor.agentRef == .builtin(.codex))
    #expect(descriptor.kind == .codex)
    #expect(descriptor.command == "/usr/local/bin/codex")
}

@Test func agentRef_customCodableRoundTrip_usesDistinguishableRepresentation() throws {
    let ref = AgentRef.custom("aider")
    let data = try JSONEncoder().encode(ref)
    let json = try #require(String(data: data, encoding: .utf8))
    let decoded = try JSONDecoder().decode(AgentRef.self, from: data)

    #expect(decoded == ref)
    #expect(json.contains("\"type\":\"custom\""))
    #expect(json.contains("\"id\":\"aider\""))
}

@Test func customAgentLoader_loadsValidEntriesAndIgnoresInvalidAndCollisions() throws {
    let url = temporaryAgentsJSONURL()
    defer { removeFile(at: url) }
    let json = """
    {
      "agents": [
        {
          "id": "codex",
          "displayName": "Collision",
          "binaryName": "collision",
          "symbolName": "xmark",
          "colorHex": "#111111",
          "statusBootstrap": "idleOnSpawnComplete"
        },
        {
          "id": "broken",
          "displayName": "Broken",
          "symbolName": "questionmark",
          "colorHex": "#222222"
        },
        {
          "id": "aider",
          "displayName": "Aider",
          "binaryName": "aider",
          "symbolName": "wrench.and.screwdriver",
          "colorHex": "#E5A53F",
          "baseArgs": ["--model", "sonnet"],
          "bypassArgs": ["--yes-always"],
          "bypassEnv": {"AIDER_AUTO_COMMITS": "0"},
          "statusBootstrap": "idleOnSpawnComplete",
          "resume": {"mode": "namedFlag", "args": ["--restore"]}
        }
      ]
    }
    """
    try Data(json.utf8).write(to: url, options: .atomic)
    var log: [String] = []

    let descriptors = CustomAgentRegistryLoader.loadDescriptors(from: url) { log.append($0) }

    let descriptor = try #require(descriptors.first)
    #expect(descriptors.count == 1)
    #expect(descriptor.ref == .custom("aider"))
    #expect(descriptor.displayName == "Aider")
    #expect(descriptor.binaryName == "aider")
    #expect(descriptor.colorRGB == AgentRGB(0xE5, 0xA5, 0x3F))
    #expect(descriptor.launchSpec.hookKind == .none)
    #expect(descriptor.launchSpec.statusBootstrap == .idleOnSpawnComplete)
    #expect(descriptor.launchSpec.baseArgs == ["--model", "sonnet"])
    #expect(descriptor.launchSpec.bypassArgs == ["--yes-always"])
    #expect(descriptor.launchSpec.bypassEnv == ["AIDER_AUTO_COMMITS": "0"])
    #expect(log.contains { $0.contains("collides with builtin") })
    #expect(log.contains { $0.contains("entry 1 ignored") })
}

@Test func customAgentLoader_nonDictionaryEntryIsSkippedWithoutCrashingAndLogged() throws {
    let url = temporaryAgentsJSONURL()
    defer { removeFile(at: url) }
    let json = """
    {
      "agents": [
        "not-a-dict",
        {
          "id": "aider",
          "displayName": "Aider",
          "binaryName": "aider",
          "symbolName": "wrench.and.screwdriver",
          "colorHex": "#E5A53F"
        }
      ]
    }
    """
    try Data(json.utf8).write(to: url, options: .atomic)
    var log: [String] = []

    let descriptors = CustomAgentRegistryLoader.loadDescriptors(from: url) { log.append($0) }

    #expect(descriptors.count == 1)
    #expect(descriptors.first?.ref == .custom("aider"))
    #expect(log.contains { $0.contains("entry 0 ignored") && $0.contains("ignored") })
}

@Test func customAgentLoader_signedHexColorEntryIsIgnoredAsInvalidColor() throws {
    let url = temporaryAgentsJSONURL()
    defer { removeFile(at: url) }
    let json = """
    {
      "agents": [
        {
          "id": "badcolor",
          "displayName": "Bad",
          "binaryName": "bad",
          "symbolName": "xmark",
          "colorHex": "+1234F"
        },
        {
          "id": "goodcolor",
          "displayName": "Good",
          "binaryName": "good",
          "symbolName": "checkmark",
          "colorHex": "#3A7BD5"
        }
      ]
    }
    """
    try Data(json.utf8).write(to: url, options: .atomic)
    var log: [String] = []

    let descriptors = CustomAgentRegistryLoader.loadDescriptors(from: url) { log.append($0) }

    #expect(descriptors.count == 1)
    #expect(descriptors.first?.ref == .custom("goodcolor"))
    #expect(log.contains { $0.contains("colorHex is invalid") })
}

@Test func customAgentLoader_invalidJSONReturnsEmptyAndLogs() throws {
    let url = temporaryAgentsJSONURL()
    defer { removeFile(at: url) }
    try Data("{ not valid json }".utf8).write(to: url, options: .atomic)
    var log: [String] = []

    let descriptors = CustomAgentRegistryLoader.loadDescriptors(from: url) { log.append($0) }

    #expect(descriptors.isEmpty)
    #expect(log.contains { $0.contains("invalid") })
}
