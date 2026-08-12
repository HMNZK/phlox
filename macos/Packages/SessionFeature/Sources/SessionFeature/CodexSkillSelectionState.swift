import CodexAppServerKit
import Foundation
import Observation

/// `skills/list` の結果を保持し、選択した skill を native input に変換する状態。
///
/// 一覧の再取得は明示的な `refresh()` だけで行う。`skills/changed` は一覧を無効化する
/// 通知なので、自動で wire request を発行せず、選択中の skill も再選択が必要になる。
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
    public private(set) var draft = ""
    public private(set) var searchTerm = ""
    public private(set) var isLoading = false
    public private(set) var isStale = false
    public private(set) var errorMessage: String?

    private let client: any CodexSkillSelectionClient
    private let sessionCWD: String
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    private var generation = 0
    private var selectionGeneration: Int?

    public init(client: any CodexSkillSelectionClient, sessionCWD: String) {
        self.client = client
        self.sessionCWD = sessionCWD
        eventTask = Task { @MainActor [weak self, client] in
            for await event in client.skillEvents {
                guard case .skillsChanged = event else { continue }
                self?.invalidate()
            }
        }
    }

    deinit {
        eventTask?.cancel()
    }

    /// 現在の session cwd だけを `skills/list` へ渡して一覧を更新する。
    public func refresh() async {
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
            filteredSkills = Self.filtered(skills, searchTerm: searchTerm)
            isLoading = false
            errorMessage = entry.errors.map(\.message).joined(separator: "\n").nilIfEmpty
            isStale = !entry.errors.isEmpty
        } catch {
            guard requestGeneration == generation else { return }
            isLoading = false
            isStale = true
            errorMessage = error.localizedDescription
        }
    }

    /// `skills/changed` を受けたときの無効化処理。再取得は呼び出し側が行う。
    public func invalidate() {
        generation += 1
        isLoading = false
        isStale = true
        errorMessage = nil
    }

    public func handle(_ event: ThreadEvent) {
        if case .skillsChanged = event {
            invalidate()
        }
    }

    public func updateSearchTerm(_ value: String) {
        searchTerm = value
        filteredSkills = Self.filtered(skills, searchTerm: value)
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
        guard !isStale else { return false }
        guard let current = skills.first(where: { Self.sameIdentity($0, skill) }), Self.isUsable(current) else {
            return false
        }
        selectedSkill = current
        selectionGeneration = generation
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
              skills.contains(where: { Self.sameIdentity($0, selectedSkill) && Self.isUsable($0) })
        else { return false }
        return true
    }

    /// draft を wire 入力へ変換する。stale な選択は送信せず `nil` を返す。
    public func inputs(for value: String? = nil) -> [UserInput]? {
        let text = value ?? draft
        guard let selectedSkill else {
            guard !isStale else { return nil }
            return text.isEmpty ? [] : [.text(text)]
        }
        guard canSendSelectedSkill else { return nil }

        let body = Self.removingDisplayToken(from: text, name: selectedSkill.name)
        var result: [UserInput] = []
        if !body.isEmpty {
            result.append(.text(body))
        }
        result.append(.skill(name: selectedSkill.name, path: selectedSkill.path))
        return result
    }

    public func nativeInputs(for value: String? = nil) -> [UserInput]? {
        inputs(for: value)
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
        return values.filter { $0.name.lowercased().hasPrefix(term) }
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
