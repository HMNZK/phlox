import Foundation

public typealias AgentRegistryLog = (String) -> Void

public enum CustomAgentRegistryLoader {
    public static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let agentsJSON = environment["PHLOX_AGENTS_JSON"], !agentsJSON.isEmpty {
            return URL(fileURLWithPath: agentsJSON)
        }
        #if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/phlox/agents.json")
        #else
        // iOS など: `homeDirectoryForCurrentUser` は利用不可。カスタムエージェント定義の読み込みは
        // Mac 専用機能であり iOS からは呼ばれないが、コンパイルを通すため documents 配下を返す。
        return URL.documentsDirectory.appending(path: ".config/phlox/agents.json")
        #endif
    }

    public static func loadDescriptors(
        from fileURL: URL = defaultURL(),
        log: AgentRegistryLog = Self.defaultLog
    ) -> [AgentDescriptor] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            log("Custom agent JSON not found: \(fileURL.path)")
            return []
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            log("Custom agent JSON could not be read: \(fileURL.path)")
            return []
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let agents = root["agents"] as? [Any] else {
            log("Custom agent JSON is invalid: \(fileURL.path)")
            return []
        }

        var descriptors: [AgentDescriptor] = []
        var seenIDs = Set<String>()
        let decoder = JSONDecoder()

        for (index, agent) in agents.enumerated() {
            guard agent is [String: Any] else {
                log("Custom agent entry \(index) ignored: not a JSON object")
                continue
            }
            do {
                let entryData = try JSONSerialization.data(withJSONObject: agent)
                let definition = try decoder.decode(CustomAgentDefinition.self, from: entryData)
                let descriptor = try definition.makeDescriptor()
                let id = descriptor.ref.id
                guard !AgentKind.allCases.contains(where: { $0.rawValue == id }) else {
                    log("Custom agent ignored because id collides with builtin: \(id)")
                    continue
                }
                guard seenIDs.insert(id).inserted else {
                    log("Custom agent ignored because id is duplicated: \(id)")
                    continue
                }
                descriptors.append(descriptor)
            } catch {
                log("Custom agent entry \(index) ignored: \(error)")
            }
        }

        return descriptors
    }

    public static func defaultLog(_ message: String) {
        let line = "Phlox: \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

private struct CustomAgentDefinition: Decodable {
    let id: String
    let displayName: String
    let binaryName: String
    let symbolName: String
    let colorHex: String
    let baseArgs: [String]?
    let bypassArgs: [String]?
    let bypassEnv: [String: String]?
    let statusBootstrap: String?
    let resume: ResumeDefinition?

    func makeDescriptor() throws -> AgentDescriptor {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw CustomAgentDefinitionError.emptyID
        }
        guard statusBootstrap == nil || statusBootstrap == "idleOnSpawnComplete" else {
            throw CustomAgentDefinitionError.unsupportedStatusBootstrap(statusBootstrap ?? "")
        }

        let resumeSpec = try resume?.makeSpec() ?? ResumeSpec()
        return AgentDescriptor(
            ref: .custom(normalizedID),
            displayName: displayName,
            binaryName: binaryName,
            symbolName: symbolName,
            colorRGB: try AgentRGB(hex: colorHex),
            bypassKey: "phlox.bypass.\(normalizedID)",
            usageProviderKind: .none,
            launchSpec: AgentLaunchSpec(
                baseArgs: baseArgs ?? [],
                bypassArgs: bypassArgs ?? [],
                bypassEnv: bypassEnv ?? [:],
                hookKind: .none,
                statusBootstrap: .idleOnSpawnComplete,
                newSessionResumeArgument: resumeSpec.newSessionArgument,
                resumeArgument: resumeSpec.resumeArgument,
                initialResumeIDStrategy: resumeSpec.initialResumeIDStrategy
            )
        )
    }
}

private struct ResumeDefinition: Decodable {
    let mode: String
    let args: [String]?

    func makeSpec() throws -> ResumeSpec {
        switch mode {
        case "none":
            return ResumeSpec()
        case "flag":
            return ResumeSpec(resumeArgument: .appendStatic(args ?? []))
        case "namedFlag":
            let args = args ?? []
            return ResumeSpec(
                newSessionArgument: .append(prefix: args),
                resumeArgument: .append(prefix: args),
                initialResumeIDStrategy: .phloxUUID
            )
        default:
            throw CustomAgentDefinitionError.unsupportedResumeMode(mode)
        }
    }
}

private struct ResumeSpec {
    var newSessionArgument: AgentResumeArgument?
    var resumeArgument: AgentResumeArgument?
    var initialResumeIDStrategy: AgentInitialResumeIDStrategy = .none
}

private enum CustomAgentDefinitionError: Error, CustomStringConvertible {
    case emptyID
    case invalidColor(String)
    case unsupportedStatusBootstrap(String)
    case unsupportedResumeMode(String)

    var description: String {
        switch self {
        case .emptyID:
            "id is empty"
        case .invalidColor(let value):
            "colorHex is invalid: \(value)"
        case .unsupportedStatusBootstrap(let value):
            "statusBootstrap is unsupported: \(value)"
        case .unsupportedResumeMode(let value):
            "resume.mode is unsupported: \(value)"
        }
    }
}

private extension AgentRGB {
    init(hex: String) throws {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6,
              raw.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = Int(raw, radix: 16) else {
            throw CustomAgentDefinitionError.invalidColor(hex)
        }
        self.init(
            (value >> 16) & 0xFF,
            (value >> 8) & 0xFF,
            value & 0xFF
        )
    }
}
