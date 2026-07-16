/// Claude/Cursor（spawn 型エージェント）のターン単位設定制御を抽象化する軽量 protocol。
/// Codex の `CodexSettingsProviding`（app-server 常駐のライブ更新）とは別物で、ここでは
/// task-9 で Kit の actor に足した置換セマンティクスの `updateSettings` だけをラップする。
/// `permissionOrMode` は Claude では permission-mode（例 acceptEdits/plan）、Cursor では
/// mode（default/plan/ask）を表す。nil はそのフラグをクリアする（置換セマンティクス）。
public protocol SpawnAgentSettingsControlling: Sendable {
    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async
}
