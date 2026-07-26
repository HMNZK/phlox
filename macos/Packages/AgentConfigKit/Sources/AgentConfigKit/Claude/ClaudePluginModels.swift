import Foundation

/// インストール済みプラグイン1件（`claude plugin list --json` の1要素）。
public struct ClaudeInstalledPlugin: Sendable, Equatable, Identifiable {
    /// `name@marketplace` 形式の識別子。CLI へ渡すのはこの値。
    public let pluginID: String
    public let version: String?
    public let scope: String?
    public let isEnabled: Bool
    public let installPath: String?
    /// このプラグインが持ち込む MCP サーバー名（あれば）。
    public let mcpServerNames: [String]

    /// 一覧の identity。**同じ `pluginID` が user と project の両方に入りうる**ため、
    /// scope まで含めないと SwiftUI の ForEach が同じ行を二重に描いてしまう。
    public var id: String { "\(pluginID)#\(scope ?? "-")" }

    public init(
        pluginID: String,
        version: String?,
        scope: String?,
        isEnabled: Bool,
        installPath: String?,
        mcpServerNames: [String]
    ) {
        self.pluginID = pluginID
        self.version = version
        self.scope = scope
        self.isEnabled = isEnabled
        self.installPath = installPath
        self.mcpServerNames = mcpServerNames
    }

    /// `name@marketplace` の名前部分。
    public var name: String {
        guard let index = pluginID.firstIndex(of: "@") else { return pluginID }
        return String(pluginID[pluginID.startIndex..<index])
    }

    /// `name@marketplace` のマーケットプレイス部分。
    public var marketplace: String? {
        guard let index = pluginID.firstIndex(of: "@") else { return nil }
        return String(pluginID[pluginID.index(after: index)...])
    }
}

/// マーケットプレイスに並んでいる（まだ入れていない）プラグイン。
public struct ClaudeAvailablePlugin: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let marketplaceName: String?

    public init(id: String, name: String, description: String?, marketplaceName: String?) {
        self.id = id
        self.name = name
        self.description = description
        self.marketplaceName = marketplaceName
    }
}

/// 登録済みマーケットプレイス。
public struct ClaudeMarketplace: Sendable, Equatable, Identifiable {
    public let name: String
    public let source: String?
    public let repo: String?
    public let installLocation: String?

    public var id: String { name }

    public init(name: String, source: String?, repo: String?, installLocation: String?) {
        self.name = name
        self.source = source
        self.repo = repo
        self.installLocation = installLocation
    }

    /// 画面に出す出どころ（`github: owner/repo` など）。
    public var originDescription: String {
        switch (source, repo) {
        case (let source?, let repo?): return "\(source): \(repo)"
        case (let source?, nil): return source
        case (nil, let repo?): return repo
        default: return "—"
        }
    }
}

/// `claude plugin list --json` / `--available --json` / `marketplace list --json` のパース。
///
/// CLI の出力に未知のキーが増えても落とさない（必要なキーだけ拾う）。
public enum ClaudePluginParsing {
    /// `claude plugin list --json` は配列、`--available` 付きは `{installed, available}` のオブジェクト。
    /// どちらの形でも installed を取り出す。
    public static func installedPlugins(from json: JSONValue) -> [ClaudeInstalledPlugin] {
        let items: [JSONValue]
        if let array = json.arrayValue {
            items = array
        } else if let array = json["installed"]?.arrayValue {
            items = array
        } else {
            return []
        }
        return items.compactMap(installedPlugin(from:))
    }

    static func installedPlugin(from item: JSONValue) -> ClaudeInstalledPlugin? {
        guard let id = item["id"]?.stringValue else { return nil }
        let mcpServerNames = (item["mcpServers"]?.objectValue?.keys).map { Array($0).sorted() } ?? []
        return ClaudeInstalledPlugin(
            pluginID: id,
            version: item["version"]?.stringValue,
            scope: item["scope"]?.stringValue,
            isEnabled: item["enabled"]?.boolValue ?? false,
            installPath: item["installPath"]?.stringValue,
            mcpServerNames: mcpServerNames
        )
    }

    public static func availablePlugins(from json: JSONValue) -> [ClaudeAvailablePlugin] {
        guard let items = json["available"]?.arrayValue else { return [] }
        return items.compactMap { item in
            guard let id = item["pluginId"]?.stringValue ?? item["id"]?.stringValue else { return nil }
            let name = item["name"]?.stringValue ?? id
            return ClaudeAvailablePlugin(
                id: id,
                name: name,
                description: item["description"]?.stringValue,
                marketplaceName: item["marketplaceName"]?.stringValue
            )
        }
    }

    public static func marketplaces(from json: JSONValue) -> [ClaudeMarketplace] {
        guard let items = json.arrayValue else { return [] }
        return items.compactMap { item in
            guard let name = item["name"]?.stringValue else { return nil }
            return ClaudeMarketplace(
                name: name,
                source: item["source"]?.stringValue,
                repo: item["repo"]?.stringValue,
                installLocation: item["installLocation"]?.stringValue
            )
        }
    }
}
