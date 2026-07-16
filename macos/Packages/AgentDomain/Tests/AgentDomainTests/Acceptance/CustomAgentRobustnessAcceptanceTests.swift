// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 監査所見: agents.json の agents 配列に辞書以外の要素があると
// JSONSerialization.data(withJSONObject:) が NSException で起動時クラッシュする。
// 監査所見(nit): AgentRGB(hex:) が Int(_:radix:) の先頭符号を受理し不正 colorHex が通る。
import Foundation
import Testing
@testable import AgentDomain

private func acceptanceAgentsJSONURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "AgentDomainAcceptance-agents-\(UUID().uuidString).json")
}

private func acceptanceRemoveFile(at url: URL) {
    try? FileManager.default.removeItem(at: url)
}

@Test func acceptance_loadDescriptors_skipsNonDictionaryEntriesWithoutCrashing() throws {
    let url = acceptanceAgentsJSONURL()
    defer { acceptanceRemoveFile(at: url) }
    // 非辞書要素（文字列・数値・配列）が混在しても、クラッシュせず辞書エントリだけ読めること
    let json = """
    {
      "agents": [
        "oops",
        42,
        ["nested"],
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
    try Data(json.utf8).write(to: url)

    var logs: [String] = []
    let descriptors = CustomAgentRegistryLoader.loadDescriptors(from: url) { logs.append($0) }

    #expect(descriptors.count == 1)
    #expect(descriptors.first?.ref.id == "aider")
    // 非辞書エントリは silent skip でなく、無視した旨をログに残すこと
    #expect(logs.contains { $0.contains("ignored") })
}

@Test func acceptance_loadDescriptors_rejectsSignedHexColor() throws {
    // "+1234F" / "-1234F" は 6 文字だが Int(_:radix:) が符号として受理してしまう。
    // 符号付き hex は不正としてエントリごと無視し、正当なエントリだけ読めること。
    for badHex in ["+1234F", "-1234F", "#+1234F"] {
        let url = acceptanceAgentsJSONURL()
        defer { acceptanceRemoveFile(at: url) }
        let json = """
        {
          "agents": [
            {
              "id": "badcolor",
              "displayName": "Bad",
              "binaryName": "bad",
              "symbolName": "xmark",
              "colorHex": "\(badHex)"
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
        try Data(json.utf8).write(to: url)

        let descriptors = CustomAgentRegistryLoader.loadDescriptors(from: url) { _ in }

        #expect(descriptors.count == 1, "colorHex \(badHex) は拒否されるべき")
        #expect(descriptors.first?.ref.id == "goodcolor")
    }
}
