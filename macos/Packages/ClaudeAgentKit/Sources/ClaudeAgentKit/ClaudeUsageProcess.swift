import Foundation
import StructuredChatKit

/// 使用量専用プロセスの所有者。シグナル終了からも MainActor を経由せず閉じられる。
public actor ClaudeUsageProcess: UsageQuerying {
    private let makeClient: @Sendable () -> ClaudeChatClient
    private var client: ClaudeChatClient?
    private var generation = 0
    private var isShutdown = false
    private var closing: Task<Void, Never>?

    public static let arguments = [
        "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--safe-mode", "--no-session-persistence", "--strict-mcp-config",
        "--mcp-config", "{\"mcpServers\":{}}", "--tools", "",
    ]

    public init(command: String, environment: [String: String],
                transportFactory: @escaping ClaudeChatClient.TransportFactory = { command, arguments, environment, directory in
                    LineDelimitedProcessTransport(command: command, arguments: arguments,
                                                  environment: environment, workingDirectory: directory)
                }) {
        makeClient = {
            ClaudeChatClient(command: command, environment: environment, transportFactory: { command, _, environment, _ in
                transportFactory(command, Self.arguments, environment, nil)
            })
        }
    }

    public func fetchRateLimits() async throws -> AgentRateLimitsSnapshot {
        await closing?.value
        guard !isShutdown else { throw ClaudeChatClientError.transportClosed }
        let expectedGeneration = generation
        let current: ClaudeChatClient
        if let client {
            current = client
        } else {
            current = makeClient()
            client = current
            do { try await current.start() }
            catch {
                if generation == expectedGeneration { client = nil }
                await current.close()
                throw error
            }
        }
        guard generation == expectedGeneration, !isShutdown else {
            await current.close()
            throw ClaudeChatClientError.transportClosed
        }
        do {
            let result = try await current.fetchRateLimits()
            guard generation == expectedGeneration, !isShutdown else { throw ClaudeChatClientError.transportClosed }
            return result
        } catch {
            if generation == expectedGeneration { await close() }
            throw error
        }
    }

    public func close() async {
        generation += 1
        let old = client
        client = nil
        let previous = closing
        let task = Task {
            await previous?.value
            await old?.close()
        }
        closing = task
        await task.value
    }

    public func shutdown() async {
        isShutdown = true
        await close()
    }
}
