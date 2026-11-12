import PhloxCore

/// Card の View identity ごとに保持し、別入力のタスク ID と手動操作を混ぜない。
struct MobileStatusCardDisclosure {
    private var overrides: [String: Bool] = [:]
    func isExpanded(_ row: MobileStatusTranscript.Row) -> Bool { overrides[row.id] ?? row.autoExpanded }
    mutating func toggle(_ row: MobileStatusTranscript.Row) { overrides[row.id] = !isExpanded(row) }
    static func isTextOnly(_ row: MobileStatusTranscript.Row) -> Bool {
        row.kind == .outside && !row.entries.contains { if case .action = $0 { return true }; return false }
    }
}
