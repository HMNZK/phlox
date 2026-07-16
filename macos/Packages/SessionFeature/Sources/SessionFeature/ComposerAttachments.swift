import Foundation
import Observation
import AgentDomain

// task-8 契約の PM スタブ。API 表面は受け入れテスト
// ComposerAttachmentAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-8.md

/// composer に添付された画像1件。
struct ComposerAttachment: Equatable, Identifiable {
    let id: UUID
    let data: Data
    let mediaType: String
    let filename: String?

    init(id: UUID = UUID(), data: Data, mediaType: String, filename: String? = nil) {
        self.id = id
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
    }
}

/// composer の添付状態（画像チップ）。上限: 1枚 4MiB・最大 4 枚・合計 raw 8MiB。
@MainActor @Observable
final class ComposerAttachmentStore {
    static let maxBytesPerImage = 4 * 1024 * 1024
    static let maxTotalRawBytes = 8 * 1024 * 1024
    static let maxCount = 4

    private(set) var attachments: [ComposerAttachment] = []
    private(set) var lastError: String?

    init(attachments: [ComposerAttachment] = []) {
        self.attachments = attachments
    }

    var totalRawBytes: Int {
        attachments.reduce(0) { $0 + $1.data.count }
    }

    var isWithinTotalRawBytesLimit: Bool {
        totalRawBytes <= Self.maxTotalRawBytes
    }

    /// 上限超過は lastError に人間可読メッセージを設定して追加しない。
    func addImage(data: Data, mediaType: String, filename: String? = nil) {
        if data.count > Self.maxBytesPerImage {
            lastError = "画像は1枚あたり4MiBまでです"
            return
        }
        if attachments.count >= Self.maxCount {
            lastError = "画像は4枚まで添付できます"
            return
        }
        if totalRawBytes + data.count > Self.maxTotalRawBytes {
            lastError = "画像は合計8MiBまでです"
            return
        }
        attachments.append(ComposerAttachment(data: data, mediaType: mediaType, filename: filename))
        lastError = nil
    }

    /// 挿入用の `@path` 参照文字列を返す（添付には積まない）。
    func addFileReference(path: String) -> String {
        "@\(path)"
    }

    func remove(id: UUID) {
        attachments.removeAll { $0.id == id }
        if attachments.count < Self.maxCount {
            lastError = nil
        }
    }

    func clear() {
        attachments.removeAll()
        lastError = nil
    }

    func setError(_ message: String) {
        lastError = message
    }
}

enum ComposerPastePolicy {
    private static let imageTypeIdentifiers: Set<String> = [
        "public.png",
        "public.jpeg",
        "public.tiff",
        "public.image",
    ]

    static func shouldInterceptImagePaste(availableTypeIdentifiers: Set<String>) -> Bool {
        return !imageTypeIdentifiers.isDisjoint(with: availableTypeIdentifiers)
    }
}

enum ComposerAttachmentCapability {
    static let unsupportedImageMessage = "画像添付は Claude のみ対応です"

    static func supportsImageAttachments(agentRef: AgentRef) -> Bool {
        agentRef == .builtin(.claudeCode)
    }
}
