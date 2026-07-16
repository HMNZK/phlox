import AgentDomain
import Foundation

/// 撤去済みの「グローバル statusLine 設置」(②-A) が過去に書き込んだ設定を、起動時に一度だけ掃除する。
///
/// 機能本体（インストーラ/トグル）は削除したが、過去に有効化したユーザーの `~/.claude/settings.json` には
/// Phlox のラッパー参照が残り得る。そのまま放置すると、Phlox がもう管理しない statusLine 記述・スクリプトが
/// 孤立して「あとから消せない」状態になる。これを防ぐためのマイグレーションとして本処理だけ残す。
///
/// 安全方針（②-A の uninstall と同じ 3-way）:
/// - settings.json の statusLine が今も Phlox 管理値のまま → manifest の元 statusLine へ復元（元が無ければキー削除）
/// - ユーザーが手で変更済み → settings.json は一切触らない（破壊しない）
/// - いずれの場合も Phlox 由来のラッパー/manifest は削除して孤立を残さない
public enum ClaudeGlobalStatusLineCleanup {
    static let managedWrapperFileName = "claude-statusline-global.sh"
    static let manifestFileName = "claude-global-statusline.manifest.json"

    /// 起動時に呼ぶ。テスト用に URL を注入可能（既定は実パス）。
    public static func cleanupLeftoverInstall(
        settingsURL: URL? = nil,
        wrapperURL: URL? = nil,
        manifestURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let home = fileManager.homeDirectoryForCurrentUser
        let appSupport = AppSupportLocator.appSupportDirectoryURL(home: home)
        let settingsURL = settingsURL ?? home.appending(path: ".claude/settings.json")
        let wrapperURL = wrapperURL ?? appSupport.appendingPathComponent(managedWrapperFileName)
        let manifestURL = manifestURL ?? appSupport.appendingPathComponent(manifestFileName)

        // どの分岐を通っても Phlox 由来のラッパー/manifest は最後に必ず除去する（孤立防止）。
        defer {
            try? fileManager.removeItem(at: wrapperURL)
            try? fileManager.removeItem(at: manifestURL)
        }

        // manifest が無ければ設置されていない（or 既に掃除済み）。settings.json は触らない。
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let managedCommand = manifest["managedStatusLineCommand"] as? String,
              let settingsData = try? Data(contentsOf: settingsURL),
              var root = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any]
        else {
            return
        }

        // statusLine が今も Phlox 管理値のときだけ元へ戻す。ユーザー変更済みなら settings.json は不変。
        let currentCommand = (root["statusLine"] as? [String: Any])?["command"] as? String
        guard currentCommand == managedCommand else { return }

        if let original = manifest["originalStatusLine"], !(original is NSNull) {
            root["statusLine"] = original
        } else {
            root.removeValue(forKey: "statusLine")
        }
        if let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: settingsURL, options: .atomic)
        }
    }
}
