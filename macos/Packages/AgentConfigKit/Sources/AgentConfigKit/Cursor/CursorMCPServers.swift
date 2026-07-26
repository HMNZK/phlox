import Foundation

/// `~/.cursor/mcp.json` に登録された MCP サーバー1件。
public struct CursorMCPServer: Sendable, Equatable, Identifiable {
    public let name: String
    /// stdio なら実行コマンド、HTTP/SSE なら URL。
    public let endpoint: String
    public let transportType: String

    public var id: String { name }

    public init(name: String, endpoint: String, transportType: String) {
        self.name = name
        self.endpoint = endpoint
        self.transportType = transportType
    }
}

/// `mcp.json` の読み書き。
///
/// `cursor-agent mcp` は一覧を人間向けテキストでしか出さないので、一覧は JSON を直接読む。
/// 有効・無効の切り替えだけは CLI（`mcp enable` / `mcp disable`）に任せる。
public enum CursorMCPServers {
    public static func servers(from root: JSONValue) -> [CursorMCPServer] {
        let entries = root["mcpServers"]?.objectValue ?? [:]
        return entries.keys.sorted().compactMap { name in
            guard let entry = entries[name] else { return nil }
            if let url = entry["url"]?.stringValue {
                return CursorMCPServer(
                    name: name,
                    endpoint: url,
                    transportType: entry["type"]?.stringValue ?? "http"
                )
            }
            guard let command = entry["command"]?.stringValue else { return nil }
            let args = entry["args"]?.stringArrayValue ?? []
            return CursorMCPServer(
                name: name,
                endpoint: ([command] + args).joined(separator: " "),
                transportType: "stdio"
            )
        }
    }

    public static func addingStdioServer(
        name: String,
        command: String,
        arguments: [String],
        to root: JSONValue
    ) -> JSONValue {
        var entry: [String: JSONValue] = ["command": .string(command)]
        if !arguments.isEmpty {
            entry["args"] = .array(arguments.map { .string($0) })
        }
        return root.setting(["mcpServers", name], to: .object(entry))
    }

    public static func addingHTTPServer(name: String, url: String, to root: JSONValue) -> JSONValue {
        root.setting(["mcpServers", name], to: .object(["url": .string(url)]))
    }

    public static func removing(name: String, from root: JSONValue) -> JSONValue {
        root.setting(["mcpServers", name], to: nil)
    }

    /// コマンド文字列を実行ファイルと引数へ割る（引用符は扱わない素朴な分割）。
    public static func splitCommand(_ text: String) -> (command: String, arguments: [String])? {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let command = parts.first else { return nil }
        return (command, Array(parts.dropFirst()))
    }
}
