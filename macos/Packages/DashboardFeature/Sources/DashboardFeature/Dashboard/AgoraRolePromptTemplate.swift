import Foundation

/// 討論参加者へ spawn 直後に注入する役割プロンプトの生成（task-3 契約・
/// AcceptanceAgoraRoleTests が凍結）。セマンティクスの正本は tasks/task-3.md。
public enum AgoraRolePromptTemplate {
    public static func prompt(
        role: String?,
        agenda: String,
        isFacilitator: Bool,
        config: AgoraDiscussionConfig
    ) -> String {
        var sections: [String] = []

        sections.append("あなたはチームビュー討論の参加者です。")

        if let role, !role.isEmpty {
            sections.append("あなたの役割: \(role)")
        }

        sections.append("議題: \(agenda)")

        sections.append(
            """
            発言規約:
            - 他者の発言は `[from 名前]` で始まる形式で届きます。帰属を確認してから応答してください。
            - 発言不要なときは本文を PASS とだけ返してください（説明や前置きは不要）。
            - PASS を除く発言数の上限は \(config.maxUtterances) 回です。
            - 参加エージェント数の上限は \(config.maxAgents) です。
            """
        )

        if isFacilitator {
            sections.append(
                """
                ファシリテーターとしての責務:
                - 必要な役割の参加者を `$PHLOX_CLI spawn --role "<役割名>" --kind claudeCode` で招集してください（このコマンドをそのまま使う。--kind は claudeCode 固定・--backend は付けない。招集した参加者への議題・規約の伝達は自動なので、個別にメッセージを送る必要はない）。
                - 議論が発散したら論点を整理し、収束に導いてください。
                - 上限到達後または打ち切り時は、議論の最終まとめを作成してください。
                """
            )
        }

        return sections.joined(separator: "\n\n")
    }
}
