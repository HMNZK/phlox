import CodexAppServerKit
import Foundation
import Observation

/// `skills/list` の結果を保持し、選択した skill を native input に変換する状態。
///
/// 一覧は `refresh()` で取得する。`skills/changed` を受けたときは stale を表示したまま
/// 自動で再取得する。メタデータとファイル一式の同一性を確認できない選択は再選択を要求する。
public protocol CodexSkillSelectionClient: Sendable {
    var skillEvents: AsyncStream<ThreadEvent> { get }
    func skillsList(_ params: SkillsListParams) async throws -> SkillsListResponse
}

public protocol CodexNativeSkillInputSending: Sendable {
    func turnStartNative(_ input: [UserInput]) async throws
}

extension CodexAppServerClient: CodexSkillSelectionClient {
    public nonisolated var skillEvents: AsyncStream<ThreadEvent> { events }
}
extension CodexStructuredAgentClient: CodexNativeSkillInputSending {}

extension CodexStructuredAgentClient: CodexSkillSelectionClient {
    public nonisolated var skillEvents: AsyncStream<ThreadEvent> { threadEvents }
}

@MainActor @Observable
public final class CodexSkillSelectionState {
    public private(set) var skills: [SkillMetadata] = []
    public private(set) var filteredSkills: [SkillMetadata] = []
    public private(set) var selectedSkill: SkillMetadata?
    public private(set) var selectedIndex: Int = 0
    public private(set) var draft = ""
    public private(set) var searchTerm = ""
    public private(set) var isLoading = false
    public private(set) var isStale = false
    /// 一覧の更新後、変更前に選択していた skill を再選択する必要があるか。
    public private(set) var requiresReselection = false
    public private(set) var errorMessage: String?

    private let client: (any CodexSkillSelectionClient)?
    @ObservationIgnored private var runtimeRefresh: (@MainActor () async -> Void)?
    private var runtimeFingerprints: [String: String] = [:]
    private var runtimeFingerprintGeneration: Int?
    private let sessionCWD: String
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTaskID = 0
    private var generation = 0
    private var selectionGeneration: Int?
    private var selectedFingerprint: String?

    public init(client: any CodexSkillSelectionClient, sessionCWD: String) {
        self.client = client
        self.sessionCWD = sessionCWD
        eventTask = Task { @MainActor [weak self, client] in
            for await event in client.skillEvents {
                guard case .skillsChanged = event else { continue }
                self?.handle(event)
            }
        }
    }

    init(projection snapshot: SessionRuntimeSkillSnapshot, sessionCWD: String,
         refresh: @escaping @MainActor () async -> Void) {
        self.client = nil
        self.sessionCWD = sessionCWD
        self.runtimeRefresh = refresh
        applyRuntimeSnapshot(snapshot)
    }

    deinit {
        eventTask?.cancel()
        refreshTask?.cancel()
    }

    /// 現在の session cwd だけを `skills/list` へ渡して一覧を更新する。
    public func refresh() async {
        if let runtimeRefresh { await runtimeRefresh(); return }
        guard let client else { return }
        generation += 1
        let requestGeneration = generation
        isLoading = true
        isStale = true
        errorMessage = nil

        do {
            let response = try await client.skillsList(
                SkillsListParams(cwds: [sessionCWD], forceReload: true)
            )
            guard requestGeneration == generation else { return }
            guard let entry = response.data.first(where: { $0.cwd == sessionCWD }) else {
                throw StateError.missingCWD(sessionCWD)
            }

            skills = Self.deduplicated(entry.skills)
            runtimeFingerprintGeneration = nil
            filteredSkills = Self.filtered(skills, searchTerm: searchTerm)
            isLoading = false
            errorMessage = entry.errors.map(\.message).joined(separator: "\n").nilIfEmpty
            isStale = !entry.errors.isEmpty
            let unchanged: Bool
            if entry.errors.isEmpty, let selectedSkill, let selectedFingerprint,
               skills.contains(where: { $0 == selectedSkill && Self.isUsable($0) }) {
                unchanged = CodexSkillFingerprint.read(skillPath: selectedSkill.path) == selectedFingerprint
            } else {
                unchanged = false
            }
            requiresReselection = selectedSkill != nil && !unchanged
            if unchanged { selectionGeneration = generation }
        } catch {
            guard requestGeneration == generation else { return }
            isLoading = false
            isStale = true
            requiresReselection = selectedSkill != nil
            errorMessage = error.localizedDescription
        }
    }

    /// 明示的に一覧を stale 化する。直接呼び出した場合は送信を止めるだけで、再取得は行わない。
    public func invalidate() {
        generation += 1
        isLoading = false
        isStale = true
        requiresReselection = selectedSkill != nil
        errorMessage = nil
    }

    public func handle(_ event: ThreadEvent) {
        if case .skillsChanged = event {
            refreshTask?.cancel()
            refreshTask = nil
            invalidate()
            scheduleRefresh()
        }
    }

    public func updateSearchTerm(_ value: String) {
        searchTerm = value
        filteredSkills = Self.filtered(skills, searchTerm: value)
        selectedIndex = min(selectedIndex, max(filteredSkills.count - 1, 0))
    }

    public func search(_ value: String) {
        updateSearchTerm(value)
    }

    public func updateDraft(_ value: String) {
        draft = value
    }

    /// 一覧に存在し、enabled かつ identity が一致する候補だけを選択する。
    @discardableResult
    public func select(_ skill: SkillMetadata) -> Bool {
        guard !isStale, !isLoading else { return false }
        guard let current = skills.first(where: { Self.sameIdentity($0, skill) }), Self.isUsable(current) else {
            return false
        }
        guard runtimeRefresh == nil || runtimeFingerprints[current.path] != nil else { return false }
        selectedSkill = current
        selectedIndex = filteredSkills.firstIndex(where: { Self.sameIdentity($0, current) }) ?? 0
        selectionGeneration = generation
        selectedFingerprint = runtimeRefresh == nil
            ? CodexSkillFingerprint.read(skillPath: current.path) : runtimeFingerprints[current.path]
        requiresReselection = false
        isStale = false
        return true
    }

    @discardableResult
    public func select(name: String, path: String) -> Bool {
        guard let skill = skills.first(where: { $0.name == name && $0.path == path }) else {
            return false
        }
        return select(skill)
    }

    public func clearSelection() {
        selectedSkill = nil
        selectionGeneration = nil
        selectedFingerprint = nil
        requiresReselection = false
    }

    var runtimeSelectionIdentity: SkillIdentity? {
        selectedSkill.map { SkillIdentity(name: $0.name, path: $0.path, runtimeFingerprint: selectedFingerprint) }
    }

    func makeRuntimeSnapshot() -> SessionRuntimeSkillSnapshot {
        if runtimeRefresh == nil, runtimeFingerprintGeneration != generation {
            var cache: [String: String?] = [:]
            runtimeFingerprints = Dictionary(skills.compactMap { skill in
                CodexSkillFingerprint.read(skillPath: skill.path, cache: &cache).map { (skill.path, $0) }
            }, uniquingKeysWith: { first, _ in first })
            runtimeFingerprintGeneration = generation
        }
        return SessionRuntimeSkillSnapshot(skills: skills, fingerprints: runtimeFingerprints,
            isLoading: isLoading, isStale: isStale, errorMessage: errorMessage)
    }

    func applyRuntimeSnapshot(_ snapshot: SessionRuntimeSkillSnapshot) {
        let unchanged = selectedSkill.map { selected in
            snapshot.skills.contains(selected) && selectedFingerprint != nil
                && snapshot.fingerprints[selected.path] == selectedFingerprint
        } ?? true
        skills = snapshot.skills
        runtimeFingerprints = snapshot.fingerprints
        filteredSkills = Self.filtered(skills, searchTerm: searchTerm)
        selectedIndex = min(selectedIndex, max(0, filteredSkills.count - 1))
        isLoading = snapshot.isLoading
        isStale = snapshot.isStale
        errorMessage = snapshot.errorMessage
        generation += 1
        runtimeFingerprintGeneration = generation
        requiresReselection = selectedSkill != nil && !unchanged
        if unchanged, selectedSkill != nil { selectionGeneration = generation }
    }

    /// 本番 composer と同じ上下/Enter 操作を surface から利用する seam。
    public func moveSelection(_ delta: Int) {
        guard !filteredSkills.isEmpty else { selectedIndex = 0; return }
        selectedIndex = min(max(selectedIndex + delta, 0), filteredSkills.count - 1)
    }

    @discardableResult
    public func acceptSelection() -> Bool {
        guard filteredSkills.indices.contains(selectedIndex) else { return false }
        return select(filteredSkills[selectedIndex])
    }

    /// 選択を composer に表示する文字列。これは送信 payload ではない。
    public var selectionDisplayText: String? {
        selectedSkill.map { "$\($0.name)" }
    }

    public var canSendSelectedSkill: Bool {
        guard let selectedSkill,
              let selectionGeneration,
              selectionGeneration == generation,
              !isStale,
              !requiresReselection,
              skills.contains(where: { Self.sameIdentity($0, selectedSkill) && Self.isUsable($0) })
        else { return false }
        return true
    }

    /// draft を wire 入力へ変換する。stale/再選択待ちの選択は送信せず `nil` を返す。
    public func inputs(for value: String? = nil) -> [UserInput]? {
        let text = value ?? draft
        guard let selectedSkill else {
            return text.isEmpty ? [] : [.text(text)]
        }
        guard canSendSelectedSkill else { return nil }

        return Self.inputs(text: text, skill: selectedSkill)
    }

    func nativeInputs(for text: String, skill: SkillIdentity) -> [UserInput]? {
        guard !isLoading, !isStale, let fingerprint = skill.runtimeFingerprint,
              let current = skills.first(where: { $0.name == skill.name && $0.path == skill.path && Self.isUsable($0) }),
              makeRuntimeSnapshot().fingerprints[skill.path] == fingerprint,
              runtimeRefresh != nil || CodexSkillFingerprint.read(skillPath: skill.path) == fingerprint
        else { return nil }
        return Self.inputs(text: text, skill: current)
    }

    private static func inputs(text: String, skill: SkillMetadata) -> [UserInput] {
        let body = removingDisplayToken(from: text, name: skill.name)
        var result: [UserInput] = []
        if !body.isEmpty {
            result.append(.text(body))
        }
        result.append(.skill(name: skill.name, path: skill.path))
        return result
    }

    public func nativeInputs(for value: String? = nil) -> [UserInput]? {
        inputs(for: value)
    }

    /// 本文を保持したまま送信を拒否した理由。UI はこれを既存のエラー表示へ載せる。
    public var invalidSelectionMessage: String? {
        guard selectedSkill != nil, !canSendSelectedSkill else { return nil }
        if isLoading || isStale {
            return "Codex skill の候補を更新中です。完了後に skill を再選択してください。"
        }
        if requiresReselection {
            return "Codex skill の候補が更新されました。送信前に skill を再選択してください。"
        }
        return "選択した Codex skill は現在の候補から送信できません。再選択してください。"
    }

    private func scheduleRefresh() {
        guard refreshTask == nil else { return }
        refreshTaskID += 1
        let taskID = refreshTaskID
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await refresh()
            guard refreshTaskID == taskID else { return }
            refreshTask = nil
        }
    }

    private enum StateError: LocalizedError {
        case missingCWD(String)

        var errorDescription: String? {
            switch self {
            case .missingCWD(let cwd): "skills/list response does not contain cwd: \(cwd)"
            }
        }
    }

    private static func deduplicated(_ values: [SkillMetadata]) -> [SkillMetadata] {
        var seen = Set<String>()
        return values.filter { skill in
            seen.insert("\(skill.name)\u{0}\(skill.path)").inserted
        }
    }

    private static func filtered(_ values: [SkillMetadata], searchTerm: String) -> [SkillMetadata] {
        guard !searchTerm.isEmpty else { return values }
        let term = searchTerm.lowercased()
        return values.filter { $0.name.lowercased().contains(term) }
    }

    private static func isUsable(_ skill: SkillMetadata) -> Bool {
        skill.enabled && !skill.name.isEmpty && !skill.path.isEmpty
    }

    private static func sameIdentity(_ lhs: SkillMetadata, _ rhs: SkillMetadata) -> Bool {
        lhs.name == rhs.name && lhs.path == rhs.path
    }

    private static func removingDisplayToken(from value: String, name: String) -> String {
        let token = "$\(name)"
        var result = value
        var searchStart = result.startIndex
        while let range = result.range(of: token, range: searchStart..<result.endIndex) {
            let before = range.lowerBound == result.startIndex ? nil : result[result.index(before: range.lowerBound)]
            let after = range.upperBound == result.endIndex ? nil : result[range.upperBound]
            guard (before == nil || before!.isWhitespace), (after == nil || after!.isWhitespace) else {
                searchStart = range.upperBound
                continue
            }
            result.removeSubrange(range)
            searchStart = range.lowerBound
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
