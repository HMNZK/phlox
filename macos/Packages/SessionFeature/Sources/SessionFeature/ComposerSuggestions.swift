import Foundation
import Observation

// task-7 契約の PM スタブ。API 表面は受け入れテスト
// ComposerSuggestionAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-7.md

/// サジェスト候補の種類。
enum SuggestionKind: Equatable {
    case slashCommand
    case fileReference
}

/// サジェスト候補1件。
struct SuggestionCandidate: Equatable, Identifiable {
    var id: String { insertionText }
    let title: String
    let insertionText: String
    let subtitle: String?
    let kind: SuggestionKind

    init(title: String, insertionText: String, subtitle: String? = nil, kind: SuggestionKind) {
        self.title = title
        self.insertionText = insertionText
        self.subtitle = subtitle
        self.kind = kind
    }
}

/// 入力テキストから検出したサジェストのトリガー。
struct SuggestionQuery: Equatable {
    let kind: SuggestionKind
    /// トリガー記号（`/` または `@`）を含む置換対象トークンの UTF16 範囲。
    let tokenRange: Range<Int>
    /// トリガー記号を除いた検索語。
    let searchTerm: String
}

/// トリガー検出の純関数。`/` はテキスト先頭のみ、`@` は空白区切りトークン先頭のみ発火。
enum SuggestionTrigger {
    static func query(text: String, cursorUTF16: Int) -> SuggestionQuery? {
        guard cursorUTF16 >= 0, cursorUTF16 <= text.utf16.count else { return nil }
        guard cursorUTF16 > 0 else { return nil }
        guard let cursorIndex = text.stringIndex(utf16Offset: cursorUTF16) else { return nil }
        let prefix = String(text[..<cursorIndex])

        if text.hasPrefix("/") {
            let term = String(prefix.dropFirst())
            return SuggestionQuery(kind: .slashCommand, tokenRange: 0..<cursorUTF16, searchTerm: term)
        }

        let tokenStartIndex = prefix.lastIndex(where: { $0.isWhitespace }).map { prefix.index(after: $0) } ?? prefix.startIndex
        let token = prefix[tokenStartIndex...]
        guard token.first == "@" else { return nil }
        let tokenStartUTF16 = tokenStartIndex.samePosition(in: text)?.utf16Offset(in: text) ?? 0
        let term = String(token.dropFirst())
        return SuggestionQuery(kind: .fileReference, tokenRange: tokenStartUTF16..<cursorUTF16, searchTerm: term)
    }
}

/// 確定時にテキストへ適用する置換。
struct SuggestionReplacement: Equatable {
    let range: Range<Int>
    let text: String
}

enum ComposerSuggestionTextReplacement {
    struct Result: Equatable {
        let text: String
        let cursorUTF16: Int
    }

    static func apply(_ replacement: SuggestionReplacement, to text: String) -> Result {
        guard replacement.range.lowerBound >= 0,
              replacement.range.upperBound <= text.utf16.count,
              let start = text.stringIndex(utf16Offset: replacement.range.lowerBound),
              let end = text.stringIndex(utf16Offset: replacement.range.upperBound)
        else {
            return Result(text: text, cursorUTF16: min(max(replacement.range.lowerBound, 0), text.utf16.count))
        }
        var next = text
        next.replaceSubrange(start..<end, with: replacement.text)
        return Result(
            text: next,
            cursorUTF16: replacement.range.lowerBound + replacement.text.utf16.count
        )
    }
}

/// composer のサジェスト状態機械。供給源は注入（テストは fake を渡す）。
@MainActor @Observable
final class ComposerSuggestionController {
    private(set) var candidates: [SuggestionCandidate] = []
    private(set) var selectedIndex: Int = 0
    var isPresented: Bool { !candidates.isEmpty }

    private let slashProvider: () -> [SuggestionCandidate]
    private let fileProvider: (String) -> [SuggestionCandidate]
    private var currentQuery: SuggestionQuery?

    /// 非同期ファイル候補走査（task-9 契約）: 走査中 true。走査中も前回候補は保持される。
    private(set) var isScanning: Bool = false
    private let asyncFileProvider: (@Sendable (String) async -> [SuggestionCandidate])?
    /// warm キャッシュの同期ピーク（miss は nil）。非 nil を返せば背景走査せず同期即応答する。
    /// MainActor 上でのみ呼ぶ（走査本体ではなくキャッシュ参照のみ）。
    private let cachedFileProvider: ((String) -> [SuggestionCandidate]?)?

    // task-9 走査 coalescing 状態機械（すべて MainActor 上で読み書きする）。
    /// 順序逆転（out-of-order completion）を排除する世代。update／invalidate（dismiss・slash・warm）で
    /// 単調増加させ、走査完了時に起動時の世代と一致する結果だけを採用する（stale は破棄）。
    private var scanGeneration: Int = 0
    /// 起動済み・未完了の走査数（＝走行中）。1 本でもある間は新規走査を起こさない（pending 化のみ）。
    private var runningScanCount: Int = 0
    /// 走行中に届いた最新クエリ（1 件だけ保持）。走行中の走査が捌けたら 1 本だけ走らせる。
    private var pendingScan: (query: SuggestionQuery, generation: Int)?

    init(
        slashProvider: @escaping () -> [SuggestionCandidate],
        fileProvider: @escaping (String) -> [SuggestionCandidate]
    ) {
        self.slashProvider = slashProvider
        self.fileProvider = fileProvider
        self.asyncFileProvider = nil
        self.cachedFileProvider = nil
    }

    /// task-9: 非同期 provider 版。update の fileReference 経路を
    /// 「MainActor 非ブロック・走査中は前回候補保持・世代管理（古いクエリの結果が
    /// 新しいクエリの結果を上書きしない）」で実装する。`cachedFileProvider` を渡すと
    /// warm キャッシュ hit 時は背景走査せず同期即応答する（miss 時のみ背景走査）。
    init(
        slashProvider: @escaping () -> [SuggestionCandidate],
        asyncFileProvider: @escaping @Sendable (String) async -> [SuggestionCandidate],
        cachedFileProvider: ((String) -> [SuggestionCandidate]?)? = nil
    ) {
        self.slashProvider = slashProvider
        self.fileProvider = { _ in [] }
        self.asyncFileProvider = asyncFileProvider
        self.cachedFileProvider = cachedFileProvider
    }

    /// テキスト・カーソル変化のたびに呼ぶ。トリガー非検出なら候補を空にする。
    /// fileReference 経路で asyncFileProvider が設定されている場合、キャッシュ miss の
    /// FS 走査は背景 Task で行い、update 自体は走査完了を待たずに即返る。
    func update(text: String, cursorUTF16: Int) {
        guard let query = SuggestionTrigger.query(text: text, cursorUTF16: cursorUTF16) else {
            dismiss()
            return
        }

        switch query.kind {
        case .slashCommand:
            applySynchronousCandidates(
                Self.filteredSlashCandidates(slashProvider(), searchTerm: query.searchTerm),
                for: query
            )
        case .fileReference:
            if asyncFileProvider != nil {
                if let cachedFileProvider, let warm = cachedFileProvider(query.searchTerm) {
                    // warm キャッシュ hit: 同期即応答（背景走査しない・挙動同値）。
                    applySynchronousCandidates(warm, for: query)
                } else {
                    // miss: 背景走査。走査中は前回候補を保持し、連打は coalescing する。
                    scheduleScan(query: query)
                }
            } else {
                applySynchronousCandidates(fileProvider(query.searchTerm), for: query)
            }
        }
    }

    /// 同期経路（スラッシュ・warm ファイル・sync init）の候補反映。
    /// 反映前に in-flight の背景走査を無効化（世代前進）し、遅延結果の混入を防ぐ。
    private func applySynchronousCandidates(_ next: [SuggestionCandidate], for query: SuggestionQuery) {
        invalidatePendingScan()
        currentQuery = next.isEmpty ? nil : query
        candidates = next
        selectedIndex = 0
    }

    /// キャッシュ miss の背景走査を要求する。update はここから即返る（await 点を跨がない）。
    /// coalescing（stage2 round2 の裁定）: 走行中の走査が 1 本でもある間は新規走査を起こさず、
    /// 最新クエリだけを pending に置き換える（同一ターンでも跨ターンでも FS 走査を増殖させない）。
    /// 走行中が無いときだけ 1 本起動する。candidates は消さない（走査中は前回候補を保持する）。
    private func scheduleScan(query: SuggestionQuery) {
        scanGeneration &+= 1
        let generation = scanGeneration
        currentQuery = query
        isScanning = true
        selectedIndex = 0

        if runningScanCount > 0 {
            // 走行中の走査がある間は新規起動しない（最新の1件だけを覚える）。
            pendingScan = (query, generation)
        } else {
            launchScan(query: query, generation: generation)
        }
    }

    /// 背景走査 Task を 1 本起動する。launchScan は「走行中が 0 のとき」だけ呼ばれるため、
    /// 走行中の走査は常に高々 1 本（並行 FS 走査は起きない）。
    private func launchScan(query: SuggestionQuery, generation: Int) {
        guard let provider = asyncFileProvider else { return }
        runningScanCount += 1
        let term = query.searchTerm
        // Task は @MainActor 文脈を継承する。await 点は `provider(term)` の 1 箇所だけで、
        // completeScan（結果反映）は await を跨がない単一 MainActor ジョブとして実行される
        // （世代・走行数の比較が race-free）。
        Task { [weak self] in
            // provider は nonisolated async のため await 中は MainActor を離れて背景で走る。
            let result = await provider(term)
            guard let self else { return }
            self.completeScan(result, query: query, generation: generation)
        }
    }

    /// 背景走査の完了結果を MainActor 上・await を跨がない単一ジョブで反映する。
    /// 起動時の世代が現在の世代と一致するときだけ採用（順序逆転で古い結果を採らない）。
    /// 走行中が捌けたら pending を 1 本だけドレインする（連打で走査が積み上がらない）。
    private func completeScan(
        _ result: [SuggestionCandidate],
        query: SuggestionQuery,
        generation: Int
    ) {
        runningScanCount -= 1
        if generation == scanGeneration {
            candidates = result
            selectedIndex = 0
            currentQuery = result.isEmpty ? nil : query
        }
        // stale（より新しい update/dismiss が発生）→ 結果は破棄。
        if runningScanCount == 0 {
            if pendingScan != nil {
                drainPendingScan()
            } else {
                isScanning = false
            }
        }
    }

    /// pending の最新クエリを 1 本だけ走らせる（世代は pending 記録時のものを引き継ぐ）。
    private func drainPendingScan() {
        guard let next = pendingScan else { return }
        pendingScan = nil
        launchScan(query: next.query, generation: next.generation)
    }

    /// in-flight／pending の走査を無効化する（dismiss・slash・warm 同期反映で使う）。
    /// 世代を前進させて走行中の走査結果を stale 化し、pending を捨てる。
    /// runningScanCount は触らない（走行中の走査は完了時に自然に減算され、結果は世代で破棄される）。
    private func invalidatePendingScan() {
        scanGeneration &+= 1
        pendingScan = nil
        isScanning = false
    }

    /// 選択を delta 移動（端でクランプ）。
    func moveSelection(_ delta: Int) {
        guard !candidates.isEmpty else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), candidates.count - 1)
    }

    /// 選択中候補の確定。非表示なら nil。
    func acceptSelected() -> SuggestionReplacement? {
        guard let currentQuery, candidates.indices.contains(selectedIndex) else { return nil }
        let candidate = candidates[selectedIndex]
        dismiss()
        return SuggestionReplacement(range: currentQuery.tokenRange, text: candidate.insertionText + " ")
    }

    func dismiss() {
        invalidatePendingScan()
        currentQuery = nil
        candidates = []
        selectedIndex = 0
    }

    func select(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        selectedIndex = index
    }

    static func production(workingDirectory: String) -> ComposerSuggestionController {
        // task-9: FS 走査本体（キャッシュ miss 時のみ発生）を背景 Task へ逃がす。
        // warm キャッシュ hit は cachedFileProvider の同期ピークで即応答し、TTL 5秒の
        // ComposerSuggestionSourceCache はそのまま温存する。
        ComposerSuggestionController(
            slashProvider: {
                ComposerSuggestionSources.slashCandidates(workingDirectory: workingDirectory)
            },
            asyncFileProvider: { term in
                ComposerSuggestionSources.fileCandidates(under: workingDirectory, matching: term)
            },
            cachedFileProvider: { term in
                ComposerSuggestionSources.cachedFileCandidates(under: workingDirectory, matching: term)
            }
        )
    }

    private static func filteredSlashCandidates(
        _ candidates: [SuggestionCandidate],
        searchTerm: String
    ) -> [SuggestionCandidate] {
        guard !searchTerm.isEmpty else { return candidates }
        let normalizedTerm = searchTerm.lowercased()
        return candidates.filter { candidate in
            let insertion = candidate.insertionText.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            let title = candidate.title.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            return insertion.hasPrefix(normalizedTerm) || title.hasPrefix(normalizedTerm)
        }
    }
}

enum ComposerSuggestionSources {
    private static let excludedDirectoryNames: Set<String> = [".git", ".build", "node_modules", "DerivedData"]
    private static let cache = ComposerSuggestionSourceCache(ttl: 5)
    private static let skillFallbackSubtitle = "Skill"

    /// ユーザードメインの TCC 保護フォルダ（Downloads / Pictures 等）の絶対パス集合。
    static let defaultProtectedDirectories: Set<String> = {
        let directories: [FileManager.SearchPathDirectory] = [
            .downloadsDirectory, .picturesDirectory, .musicDirectory,
            .desktopDirectory, .documentDirectory, .moviesDirectory,
        ]
        return Set(directories.compactMap {
            FileManager.default.urls(for: $0, in: .userDomainMask).first?.path
        })
    }()

    private struct SkillEntry {
        let name: String
        let subtitle: String
    }

    static let builtinSlashCommands: [SuggestionCandidate] = [
        SuggestionCandidate(title: "/compact", insertionText: "/compact", subtitle: "Compact conversation context", kind: .slashCommand),
        SuggestionCandidate(title: "/clear", insertionText: "/clear", subtitle: "Clear conversation history", kind: .slashCommand),
        SuggestionCandidate(title: "/model", insertionText: "/model", subtitle: "Select model", kind: .slashCommand),
        SuggestionCandidate(title: "/help", insertionText: "/help", subtitle: "Show available commands", kind: .slashCommand),
        SuggestionCandidate(title: "/init", insertionText: "/init", subtitle: "Initialize project memory", kind: .slashCommand),
    ]

    static func slashCandidates(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> [SuggestionCandidate] {
        let workspacePath = normalizedWorkingDirectory(workingDirectory)
        return cache.slashCandidates(
            homeDirectory: homeDirectory.standardizedFileURL.path,
            workingDirectory: workspacePath
        ) {
            uncachedSlashCandidates(homeDirectory: homeDirectory, workingDirectory: workspacePath)
        }
    }

    private static func uncachedSlashCandidates(
        homeDirectory: URL,
        workingDirectory: String
    ) -> [SuggestionCandidate] {
        var candidates = builtinSlashCommands
        let workspaceURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        let commandDirectories = [
            homeDirectory.appending(path: ".claude/commands", directoryHint: .isDirectory),
            workspaceURL.appending(path: ".claude/commands", directoryHint: .isDirectory),
        ]
        let skillDirectories = [
            homeDirectory.appending(path: ".claude/skills", directoryHint: .isDirectory),
            workspaceURL.appending(path: ".claude/skills", directoryHint: .isDirectory),
        ]

        for name in commandDirectories.flatMap(commandNames(in:)) {
            candidates.append(SuggestionCandidate(title: "/\(name)", insertionText: "/\(name)", subtitle: "Custom command", kind: .slashCommand))
        }
        for skill in skillDirectories.flatMap(skillEntries(in:)) {
            candidates.append(SuggestionCandidate(title: "/\(skill.name)", insertionText: "/\(skill.name)", subtitle: skill.subtitle, kind: .slashCommand))
        }
        return deduplicated(candidates)
    }

    static func fileCandidates(
        under workingDirectory: String,
        matching searchTerm: String,
        maxDepth: Int = 4,
        maxEntries: Int = 2000,
        protectedDirectories: Set<String> = defaultProtectedDirectories
    ) -> [SuggestionCandidate] {
        let rootPath = normalizedWorkingDirectory(workingDirectory)
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let protectedPaths = standardizedProtectedPaths(protectedDirectories)
        let paths = cache.filePaths(workingDirectory: rootPath, maxDepth: maxDepth, maxEntries: maxEntries) {
            boundedRelativeFilePaths(
                under: rootURL,
                maxDepth: maxDepth,
                maxEntries: maxEntries,
                protectedPaths: protectedPaths
            )
        }
        return candidates(fromPaths: paths, matching: searchTerm)
    }

    /// warm キャッシュの同期ピーク（task-9）。TTL 内にキャッシュ済みのパス集合があれば
    /// フィルタ・整形して返す。miss（未キャッシュ／期限切れ）なら nil を返し、走査は行わない。
    /// FS 走査を一切起こさないため MainActor 上から安全に呼べる。
    static func cachedFileCandidates(
        under workingDirectory: String,
        matching searchTerm: String,
        maxDepth: Int = 4,
        maxEntries: Int = 2000
    ) -> [SuggestionCandidate]? {
        let rootPath = normalizedWorkingDirectory(workingDirectory)
        guard let paths = cache.cachedFilePaths(
            workingDirectory: rootPath,
            maxDepth: maxDepth,
            maxEntries: maxEntries
        ) else {
            return nil
        }
        return candidates(fromPaths: paths, matching: searchTerm)
    }

    /// 走査済みパス集合に対する検索語フィルタ・整形（前方一致を部分一致より優先）。
    /// fileCandidates と cachedFileCandidates で共有し、内容・順序・フィルタ規則を一致させる。
    private static func candidates(
        fromPaths paths: [String],
        matching searchTerm: String
    ) -> [SuggestionCandidate] {
        let term = searchTerm.lowercased()
        let filtered: [String]
        if term.isEmpty {
            filtered = paths
        } else {
            let prefixMatches = paths.filter { $0.lowercased().hasPrefix(term) || lastPathComponent($0).lowercased().hasPrefix(term) }
            let prefixSet = Set(prefixMatches)
            let partialMatches = paths.filter { path in
                !prefixSet.contains(path) && path.lowercased().contains(term)
            }
            filtered = prefixMatches + partialMatches
        }

        return filtered.map { path in
            SuggestionCandidate(title: path, insertionText: "@\(path)", subtitle: nil, kind: .fileReference)
        }
    }

    private static func boundedRelativeFilePaths(
        under rootURL: URL,
        maxDepth: Int,
        maxEntries: Int,
        protectedPaths: Set<String>
    ) -> [String] {
        guard maxDepth >= 0, maxEntries > 0 else { return [] }
        var results: [String] = []
        var visitedEntries = 0
        collectFiles(
            in: rootURL,
            rootURL: rootURL,
            depth: 1,
            maxDepth: maxDepth,
            maxEntries: maxEntries,
            protectedPaths: protectedPaths,
            visitedEntries: &visitedEntries,
            results: &results
        )
        return results.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func collectFiles(
        in directory: URL,
        rootURL: URL,
        depth: Int,
        maxDepth: Int,
        maxEntries: Int,
        protectedPaths: Set<String>,
        visitedEntries: inout Int,
        results: inout [String]
    ) {
        guard depth <= maxDepth, visitedEntries < maxEntries else { return }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        let rootPath = rootURL.standardizedFileURL.path
        for entry in entries.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            guard visitedEntries < maxEntries else { break }
            visitedEntries += 1
            guard let values = try? entry.resourceValues(forKeys: keys), values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                guard !excludedDirectoryNames.contains(entry.lastPathComponent) else { continue }
                let childPath = entry.standardizedFileURL.path
                if childPath != rootPath, protectedPaths.contains(childPath) {
                    continue
                }
                collectFiles(
                    in: entry,
                    rootURL: rootURL,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    maxEntries: maxEntries,
                    protectedPaths: protectedPaths,
                    visitedEntries: &visitedEntries,
                    results: &results
                )
            } else if values.isRegularFile == true {
                results.append(relativePath(for: entry, rootURL: rootURL))
            }
        }
    }

    private static func standardizedProtectedPaths(_ paths: Set<String>) -> Set<String> {
        Set(paths.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path })
    }

    private static func commandNames(in directory: URL) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func skillEntries(in directory: URL) -> [SkillEntry] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .map { url in
                SkillEntry(name: url.lastPathComponent, subtitle: skillSubtitle(in: url))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func skillSubtitle(in skillDirectory: URL) -> String {
        let skillFile = skillDirectory.appending(path: "SKILL.md")
        guard let content = try? String(contentsOf: skillFile, encoding: .utf8),
              let description = frontmatterDescription(in: content)
        else {
            return skillFallbackSubtitle
        }
        return description
    }

    private static func frontmatterDescription(in content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }

        var index = 1
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != "---" else { return nil }

            if let valueStart = line.firstIndex(of: ":") {
                let key = line[..<valueStart].trimmingCharacters(in: .whitespacesAndNewlines)
                if key == "description" {
                    let rawValue = line[line.index(after: valueStart)...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return normalizedDescription(rawValue, following: lines[(index + 1)...])
                }
            }
            index += 1
        }
        return nil
    }

    private static func normalizedDescription(
        _ rawValue: String,
        following lines: ArraySlice<String>
    ) -> String? {
        if rawValue == "|" || rawValue == ">" {
            let blockLines = lines.prefix { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed != "---" else { return false }
                return trimmed.isEmpty || line.first?.isWhitespace == true
            }
            let description = blockLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: rawValue == ">" ? " " : "\n")
            return description.nilIfEmpty
        }

        let unquoted = rawValue.strippingMatchingQuotes()
        return unquoted.nilIfEmpty
    }

    private static func deduplicated(_ candidates: [SuggestionCandidate]) -> [SuggestionCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            seen.insert(candidate.insertionText).inserted
        }
    }

    private static func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return fileURL.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func normalizedWorkingDirectory(_ path: String) -> String {
        guard !path.isEmpty else { return FileManager.default.currentDirectoryPath }
        return (path as NSString).expandingTildeInPath
    }

    private static func lastPathComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

private final class ComposerSuggestionSourceCache: @unchecked Sendable {
    private struct SlashKey: Hashable {
        let homeDirectory: String
        let workingDirectory: String
    }

    private struct FileKey: Hashable {
        let workingDirectory: String
        let maxDepth: Int
        let maxEntries: Int
    }

    private struct Entry<Value> {
        let timestamp: Date
        let value: Value
    }

    private let ttl: TimeInterval
    private let lock = NSLock()
    private var slashEntries: [SlashKey: Entry<[SuggestionCandidate]>] = [:]
    private var fileEntries: [FileKey: Entry<[String]>] = [:]

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func slashCandidates(
        homeDirectory: String,
        workingDirectory: String,
        load: () -> [SuggestionCandidate]
    ) -> [SuggestionCandidate] {
        let key = SlashKey(homeDirectory: homeDirectory, workingDirectory: workingDirectory)
        if let cached = cachedSlashCandidates(for: key, now: Date()) {
            return cached
        }

        let loaded = load()
        lock.withLock {
            slashEntries[key] = Entry(timestamp: Date(), value: loaded)
        }
        return loaded
    }

    func filePaths(
        workingDirectory: String,
        maxDepth: Int,
        maxEntries: Int,
        load: () -> [String]
    ) -> [String] {
        let key = FileKey(workingDirectory: workingDirectory, maxDepth: maxDepth, maxEntries: maxEntries)
        if let cached = cachedFilePaths(for: key, now: Date()) {
            return cached
        }

        let loaded = load()
        lock.withLock {
            fileEntries[key] = Entry(timestamp: Date(), value: loaded)
        }
        return loaded
    }

    /// TTL 内にキャッシュ済みのパス集合を（走査を起こさず）返す。miss なら nil（task-9 warm ピーク）。
    func cachedFilePaths(
        workingDirectory: String,
        maxDepth: Int,
        maxEntries: Int
    ) -> [String]? {
        let key = FileKey(workingDirectory: workingDirectory, maxDepth: maxDepth, maxEntries: maxEntries)
        return cachedFilePaths(for: key, now: Date())
    }

    private func cachedSlashCandidates(for key: SlashKey, now: Date) -> [SuggestionCandidate]? {
        lock.withLock {
            guard let entry = slashEntries[key], now.timeIntervalSince(entry.timestamp) < ttl else { return nil }
            return entry.value
        }
    }

    private func cachedFilePaths(for key: FileKey, now: Date) -> [String]? {
        lock.withLock {
            guard let entry = fileEntries[key], now.timeIntervalSince(entry.timestamp) < ttl else { return nil }
            return entry.value
        }
    }
}

private extension NSLock {
    func withLock<Value>(_ body: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return body()
    }
}

private extension String {
    func stringIndex(utf16Offset: Int) -> String.Index? {
        guard utf16Offset >= 0, utf16Offset <= utf16.count else { return nil }
        let utf16Index = utf16.index(utf16.startIndex, offsetBy: utf16Offset)
        return utf16Index.samePosition(in: self)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func strippingMatchingQuotes() -> String {
        guard count >= 2,
              let first,
              let last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return self
        }
        return String(dropFirst().dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String.Index {
    func utf16Offset(in string: String) -> Int {
        string.utf16.distance(from: string.utf16.startIndex, to: samePosition(in: string.utf16) ?? string.utf16.startIndex)
    }
}
