import AgentDomain
import Foundation

/// セッションが `system/init` で申告した利用可能スラッシュコマンド一覧を、
/// エージェント × 作業ディレクトリ単位で `UserDefaults` に永続化するストア。
///
/// 同じキーへの再記録は全量スナップショットで置き換える（後勝ち）。
/// 空配列・上限超過は「申告が信用できない」とみなして保存せず、既存値も消さない。
public struct AvailableCommandsStore: Sendable {
    private static let keyPrefix = "phlox.availableCommands"
    /// 1 キーに保存するコマンドの上限件数。これを超える申告は保存しない。
    static let maxCommandCount = 300

    // UserDefaults は Sendable 宣言を持たないが、Apple のドキュメントどおりスレッド安全。
    // 契約（task-3.md）の「スレッド安全は UserDefaults の保証に委ねる」に従い unsafe を明示する。
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .phloxDefaults()) {
        self.defaults = defaults
    }

    public func record(agentRef: AgentRef, workingDirectory: String?, commands: [String]) {
        guard !commands.isEmpty, commands.count <= Self.maxCommandCount else {
            // 既存値は保持する（removeObject を呼ばない）。
            return
        }
        defaults.set(commands, forKey: Self.key(agentRef: agentRef, workingDirectory: workingDirectory))
    }

    public func commands(agentRef: AgentRef, workingDirectory: String?) -> [String]? {
        defaults.stringArray(forKey: Self.key(agentRef: agentRef, workingDirectory: workingDirectory))
    }

    // MARK: - キー

    static func key(agentRef: AgentRef, workingDirectory: String?) -> String {
        "\(keyPrefix).\(agentRef.id).\(normalizedWorkingDirectory(workingDirectory))"
    }

    /// 永続キーを安定させるための作業ディレクトリ正規化。
    /// 補完側（`ComposerSuggestions`）の cwd 正規化とは目的が違う独立の処理で、共有しない。
    static func normalizedWorkingDirectory(_ workingDirectory: String?) -> String {
        // 1. nil / 空文字は「作業ディレクトリなし」を表す 1 つのキーへ落とす。
        guard let workingDirectory, !workingDirectory.isEmpty else { return "" }
        // 2. チルダ展開。
        let expanded = (workingDirectory as NSString).expandingTildeInPath
        // 3. `.` `..` の解決。
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        // 4. 末尾スラッシュ除去（ルート `/` は除く）。
        var trimmed = standardized
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
