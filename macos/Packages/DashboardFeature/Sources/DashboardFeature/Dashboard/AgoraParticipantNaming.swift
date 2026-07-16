import Foundation

// task-3 契約の PM スタブ。API 表面は受け入れテスト
// AcceptanceAgoraRenameTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-3.md

/// アゴラ討論参加者の役割ベース命名（純関数）。
/// 討論への参加登録時に、セッション名を役割名へ揃えるための名前を決める。
public enum AgoraParticipantNaming {
    /// role が nil/空なら nil（リネームしない）。役割名が既存名と衝突する場合は
    /// 「役割名 2」「役割名 3」… の形で最小の空き連番を付与する。
    public static func name(forRole role: String?, existingNames: Set<String>) -> String? {
        guard let role else { return nil }
        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRole.isEmpty else { return nil }

        if !existingNames.contains(trimmedRole) {
            return trimmedRole
        }

        var suffix = 2
        while existingNames.contains("\(trimmedRole) \(suffix)") {
            suffix += 1
        }
        return "\(trimmedRole) \(suffix)"
    }
}
