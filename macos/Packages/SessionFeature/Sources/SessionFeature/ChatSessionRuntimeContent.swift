import CryptoKit
import Foundation
import StructuredChatKit

private struct PendingContentValue {
    let id: String
    let data: Data
    let entry: SessionRuntimePendingEntry
}

struct RuntimeContentChunkCache {
    let kind: SessionRuntimeContentMarker.Kind
    let id: String
    let digest: String
    let itemIndex: Int?
    var transcriptRevision: Int
    let token: UUID
    let data: Data
}

struct RuntimePresentationChunkCache {
    let executionID: UUID
    let revision: UInt64
    let token: UUID
    let data: Data?
    let digest: String?
}

extension ChatHistorySummary {
    init(messageCount: Int, reachesLimit: Bool, lastMessage: String?) {
        self.messageCount = messageCount
        self.reachesLimit = reachesLimit
        self.lastMessage = lastMessage
    }
}

extension ChatSessionViewModel {
    public func runtimeContent(for request: SessionRuntimeContentRequest) throws -> SessionRuntimeContentResponse {
        guard request.sessionID == id, request.executionID == executionID else {
            throw SessionRuntimeContentError.staleContent
        }
        if runtimeContentCacheExecutionID != executionID {
            runtimeContentPrefixHashes = [SHA256()]
            runtimeContentPrefixRevision = nil
            clearRuntimeContentChunkCache()
            clearRuntimePresentationChunkCache()
            runtimeContentCacheExecutionID = executionID
        }
        let response: SessionRuntimeContentResponse
        switch request.target {
        case .ptySnapshot:
            throw SessionRuntimeContentError.invalidRequest
        case .chatTail:
            response = .chatPage(try makeChatContentPage(before: transcript.count))
        case .chatBefore(let cursor):
            try Self.validate(cursor: cursor)
            guard cursor.index < transcript.count,
                  transcript[cursor.index].id == cursor.anchorID,
                  try chatPrefixDigest(through: cursor.index) == cursor.prefixDigest else {
                throw SessionRuntimeContentError.staleContent
            }
            response = .chatPage(try makeChatContentPage(before: cursor.index))
        case .pending(let cursor):
            response = .pendingPage(try makePendingContentPage(cursor: cursor))
        case .itemChunk(let itemID, let digest, let offset):
            let cached = runtimeContentChunkCache
            let index: Int?
            if let cached, cached.kind == .chatItem, cached.id == itemID,
               cached.transcriptRevision == transcriptRevision, let itemIndex = cached.itemIndex,
               itemIndex < transcript.count, transcript[itemIndex].id == itemID {
                index = itemIndex
            } else {
                index = transcript.firstIndex(where: { $0.id == itemID })
            }
            guard let index else { throw SessionRuntimeContentError.notFound }
            let data: Data
            if let cached, cached.kind == .chatItem, cached.id == itemID,
               cached.digest == digest, cached.itemIndex == index,
               cached.transcriptRevision == transcriptRevision {
                data = cached.data
            } else {
                data = try Self.contentEncoder.encode(transcript[index])
                guard Self.contentDigest(data) == digest else { throw SessionRuntimeContentError.staleContent }
                storeRuntimeContentChunkCache(kind: .chatItem, id: itemID, digest: digest,
                    itemIndex: index, data: data)
            }
            let chunk = try makeContentChunk(id: itemID, digest: digest, offset: offset, data: data)
            if chunk.nextOffset == nil { clearRuntimeContentChunkCache() }
            response = .chunk(chunk)
        case .approvalChunk(let approvalID, let digest, let offset):
            guard let approval = pendingApprovals.first(where: { $0.id == approvalID }) else {
                throw SessionRuntimeContentError.notFound
            }
            let data: Data
            if let cached = runtimeContentChunkCache, cached.kind == .approval,
               cached.id == approvalID.uuidString, cached.digest == digest {
                data = cached.data
            } else {
                data = try Self.contentEncoder.encode(approval)
                guard Self.contentDigest(data) == digest else { throw SessionRuntimeContentError.staleContent }
                storeRuntimeContentChunkCache(kind: .approval, id: approvalID.uuidString,
                    digest: digest, itemIndex: nil, data: data)
            }
            let chunk = try makeContentChunk(id: approvalID.uuidString, digest: digest,
                offset: offset, data: data)
            if chunk.nextOffset == nil { clearRuntimeContentChunkCache() }
            response = .chunk(chunk)
        case .chatPresentation(let offset, let digest):
            guard offset >= 0, offset == 0 || digest != nil else { throw SessionRuntimeContentError.invalidRequest }
            let cache = try loadRuntimePresentationChunkCache()
            guard let data = cache.data, let currentDigest = cache.digest else {
                throw SessionRuntimeContentError.invalidRequest
            }
            if let digest, digest != currentDigest { throw SessionRuntimeContentError.staleContent }
            let chunk = try makeContentChunk(id: "chat-presentation",
                digest: currentDigest, offset: offset, data: data)
            if chunk.nextOffset == nil { clearRuntimePresentationChunkCache() }
            response = .presentationChunk(chunk)
        }
        guard try Self.contentEncoder.encode(response).count <= SessionRuntimeContentLimits.maximumResponseBytes else {
            throw SessionRuntimeContentError.invalidRequest
        }
        return response
    }

    private func makeChatContentPage(before end: Int) throws -> SessionRuntimeChatPage {
        var entries: [SessionRuntimeChatPageEntry] = []
        var usage: [String: TurnUsage] = [:]
        var entryBytes = 0
        var start = end
        while start > 0, entries.count < SessionRuntimeContentLimits.maximumItemsPerPage {
            let candidateIndex = start - 1
            let item = transcript[candidateIndex]
            let itemData = try Self.contentEncoder.encode(item)
            let entry: SessionRuntimeChatPageEntry
            if itemData.count > SessionRuntimeContentLimits.maximumInlineItemBytes {
                entry = .oversized(.init(kind: .chatItem, id: item.id,
                    digest: Self.contentDigest(itemData), totalBytes: itemData.count, preview: item.plainText))
            } else {
                entry = .item(item)
            }
            var candidateUsage = usage
            if let value = turnUsageByItemID[item.id] { candidateUsage[item.id] = value }
            let envelope = SessionRuntimeChatPage(sessionID: id, executionID: executionID,
                transcriptRevision: transcriptRevision, totalCount: transcript.count,
                startIndex: candidateIndex, entries: [],
                olderCursor: candidateIndex > 0 ? .init(index: candidateIndex,
                    anchorID: item.id, prefixDigest: Self.placeholderDigest) : nil,
                turnUsageByItemID: [:])
            let encodedEntryBytes = try Self.contentEncoder.encode(entry).count
            let encodedUsageBytes = try Self.contentEncoder.encode(candidateUsage).count
            let candidateBytes = try Self.contentEncoder.encode(SessionRuntimeContentResponse.chatPage(envelope)).count
                + entryBytes + encodedEntryBytes + entries.count + encodedUsageBytes - 2
            if candidateBytes > SessionRuntimeContentLimits.maximumResponseBytes {
                break
            }
            entries.insert(entry, at: 0)
            entryBytes += encodedEntryBytes
            usage = candidateUsage
            start = candidateIndex
        }
        guard end == 0 || start < end else { throw SessionRuntimeContentError.invalidRequest }
        let cursor: SessionRuntimeContentCursor?
        if start > 0 {
            cursor = try .init(index: start, anchorID: transcript[start].id,
                prefixDigest: chatPrefixDigest(through: start))
        } else {
            cursor = nil
        }
        return SessionRuntimeChatPage(sessionID: id, executionID: executionID,
            transcriptRevision: transcriptRevision, totalCount: transcript.count,
            startIndex: start, entries: entries, olderCursor: cursor, turnUsageByItemID: usage)
    }

    private func makePendingContentPage(cursor: SessionRuntimeContentCursor?) throws -> SessionRuntimePendingPage {
        let values = try pendingContentValues()
        let start: Int
        if let cursor {
            try Self.validate(cursor: cursor)
            guard cursor.index <= values.count,
                  values[cursor.index - 1].id == cursor.anchorID,
                  Self.prefixDigest(values.prefix(cursor.index).map(\.data)) == cursor.prefixDigest else {
                throw SessionRuntimeContentError.staleContent
            }
            start = cursor.index
        } else {
            start = 0
        }
        var entries: [SessionRuntimePendingEntry] = []
        var next = start
        while next < values.count, entries.count < SessionRuntimeContentLimits.maximumItemsPerPage {
            let value = values[next]
            let entry: SessionRuntimePendingEntry
            if value.data.count > SessionRuntimeContentLimits.maximumInlineItemBytes {
                let kind: SessionRuntimeContentMarker.Kind
                if case .approval = value.entry { kind = .approval } else { kind = .chatItem }
                let preview: String
                switch value.entry {
                case .approval(let approval): preview = approval.prompt
                case .question(let item), .relatedItem(let item): preview = item.plainText
                case .oversized: preview = ""
                }
                entry = .oversized(.init(kind: kind, id: value.id,
                    digest: Self.contentDigest(value.data), totalBytes: value.data.count, preview: preview))
            } else {
                entry = value.entry
            }
            let following = next + 1
            let candidate = SessionRuntimePendingPage(sessionID: id, executionID: executionID,
                transcriptRevision: transcriptRevision, totalCount: values.count,
                entries: entries + [entry], nextCursor: following < values.count
                    ? .init(index: following, anchorID: value.id, prefixDigest: Self.placeholderDigest) : nil)
            if try Self.contentEncoder.encode(SessionRuntimeContentResponse.pendingPage(candidate)).count
                > SessionRuntimeContentLimits.maximumResponseBytes {
                break
            }
            entries.append(entry)
            next = following
        }
        guard start == values.count || next > start else { throw SessionRuntimeContentError.invalidRequest }
        let nextCursor: SessionRuntimeContentCursor?
        if next < values.count {
            nextCursor = .init(index: next, anchorID: values[next - 1].id,
                prefixDigest: Self.prefixDigest(values.prefix(next).map(\.data)))
        } else {
            nextCursor = nil
        }
        return SessionRuntimePendingPage(sessionID: id, executionID: executionID,
            transcriptRevision: transcriptRevision, totalCount: values.count,
            entries: entries, nextCursor: nextCursor)
    }

    private func pendingContentValues() throws -> [PendingContentValue] {
        var values: [PendingContentValue] = []
        for approval in pendingApprovals {
            values.append(.init(id: approval.id.uuidString,
                data: try Self.contentEncoder.encode(approval), entry: .approval(approval)))
            if let related = transcript.first(where: { $0.id == approval.itemId }) {
                values.append(.init(id: related.id, data: try Self.contentEncoder.encode(related),
                    entry: .relatedItem(related)))
            }
        }
        for item in transcript {
            guard case .userQuestion(_, _, _, _, .pending, _) = item else { continue }
            values.append(.init(id: item.id, data: try Self.contentEncoder.encode(item),
                entry: .question(item)))
        }
        return values
    }

    func clearRuntimeContentChunkCache() {
        runtimeContentChunkCacheExpiry?.cancel()
        runtimeContentChunkCacheExpiry = nil
        runtimeContentChunkCache = nil
    }

    func clearRuntimePresentationChunkCache() {
        runtimePresentationChunkCacheExpiry?.cancel()
        runtimePresentationChunkCacheExpiry = nil
        runtimePresentationChunkCache = nil
    }

    private func loadRuntimePresentationChunkCache() throws -> RuntimePresentationChunkCache {
        if let cache = runtimePresentationChunkCache,
           cache.executionID == executionID, cache.revision == runtimePresentationRevision {
            return cache
        }
        clearRuntimePresentationChunkCache()
        let data = try Self.contentEncoder.encode(makeRuntimeChatPresentation())
        let isBounded = data.count <= SessionRuntimeContentLimits.maximumPresentationBytes
        let token = UUID()
        let cache = RuntimePresentationChunkCache(executionID: executionID,
            revision: runtimePresentationRevision, token: token,
            data: isBounded ? data : nil, digest: isBounded ? Self.contentDigest(data) : nil)
        runtimePresentationChunkCache = cache
        runtimePresentationChunkCacheExpiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return }
            guard let self, self.runtimePresentationChunkCache?.token == token else { return }
            self.runtimePresentationChunkCache = nil
            self.runtimePresentationChunkCacheExpiry = nil
        }
        return cache
    }

    private func storeRuntimeContentChunkCache(kind: SessionRuntimeContentMarker.Kind,
        id: String, digest: String, itemIndex: Int?, data: Data) {
        clearRuntimeContentChunkCache()
        let token = UUID()
        runtimeContentChunkCache = RuntimeContentChunkCache(kind: kind, id: id,
            digest: digest, itemIndex: itemIndex, transcriptRevision: transcriptRevision,
            token: token, data: data)
        runtimeContentChunkCacheExpiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return }
            guard let self, self.runtimeContentChunkCache?.token == token else { return }
            self.runtimeContentChunkCache = nil
            self.runtimeContentChunkCacheExpiry = nil
        }
    }

    private func makeContentChunk(id itemID: String, digest: String, offset: Int, data: Data) throws -> SessionRuntimeContentChunk {
        guard offset >= 0, Self.isDigest(digest), !itemID.isEmpty else {
            throw SessionRuntimeContentError.invalidRequest
        }
        guard offset <= data.count else { throw SessionRuntimeContentError.staleContent }
        let end = offset + min(SessionRuntimeContentLimits.maximumChunkBytes, data.count - offset)
        return .init(sessionID: id, executionID: executionID, id: itemID, digest: digest,
            offset: offset, totalBytes: data.count, bytes: data.subdata(in: offset..<end),
            nextOffset: end < data.count ? end : nil)
    }

    private func chatPrefixDigest(through index: Int) throws -> String {
        if runtimeContentPrefixRevision != transcriptRevision
            || runtimeContentPrefixHashes.count > transcript.count + 1 {
            runtimeContentPrefixHashes = [SHA256()]
            runtimeContentPrefixRevision = transcriptRevision
        }
        if runtimeContentPrefixHashes.count <= index + 1 {
            let encoder = Self.contentEncoder
            for item in transcript[(runtimeContentPrefixHashes.count - 1)...index] {
                var hash = runtimeContentPrefixHashes.last!
                let data = try encoder.encode(item)
                var length = UInt64(data.count).bigEndian
                withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
                hash.update(data: data)
                runtimeContentPrefixHashes.append(hash)
            }
        }
        var hash = runtimeContentPrefixHashes[index + 1]
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static let placeholderDigest = String(repeating: "0", count: 64)
    private static func validate(cursor: SessionRuntimeContentCursor) throws {
        guard cursor.index > 0, !cursor.anchorID.isEmpty, isDigest(cursor.prefixDigest) else {
            throw SessionRuntimeContentError.invalidRequest
        }
    }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static var contentEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    private static func contentDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func prefixDigest<S: Sequence>(_ values: S) -> String where S.Element == Data {
        var hash = SHA256()
        for data in values {
            var length = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum SessionRuntimeContentLimits {
    public static let maximumResponseBytes = 4 * 1024 * 1024
    public static let maximumInlineItemBytes = 2 * 1024 * 1024
    public static let maximumChunkBytes = 1024 * 1024
    public static let maximumItemsPerPage = 50
    public static let maximumEncodedRequestBytes = 8192
    public static let maximumPresentationBytes = 16 * 1024 * 1024
}
