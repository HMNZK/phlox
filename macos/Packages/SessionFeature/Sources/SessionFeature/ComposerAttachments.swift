import Foundation
import Observation
import AgentDomain

// task-8 契約の PM スタブ。API 表面は受け入れテスト
// ComposerAttachmentAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-8.md

/// composer に添付された画像1件。
struct ComposerAttachment: Equatable, Identifiable {
    let id: UUID
    /// 本文の `[Image #N]` と対応する表示番号（1始まり・欠番は詰めない）。task-2 契約。
    let number: Int
    let data: Data
    let mediaType: String
    let filename: String?

    init(id: UUID = UUID(), number: Int = 1, data: Data, mediaType: String, filename: String? = nil) {
        self.id = id
        self.number = number
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
    }
}

// task-2 契約の PM スタブ。API 表面は受け入れテスト
// ComposerImageNumberingAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-2.md

/// 画像ペーストの処理結果。`.unsupported` のときだけ通常のテキストペーストへフォールバックする。
enum ComposerPasteImageOutcome: Equatable {
    case unsupported
    case rejected
    case attached(number: Int)
}

/// 添付チップの表示（純関数）。
enum ComposerAttachmentChipPresentation {
    static func badge(for attachment: ComposerAttachment) -> String {
        "#\(attachment.number)"
    }

    static func title(for attachment: ComposerAttachment) -> String {
        attachment.filename ?? attachment.mediaType
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
    /// 受理したときだけ採番済みの添付を返す（task-2 契約。PM スタブは常に nil）。
    @discardableResult
    func addImage(data: Data, mediaType: String, filename: String? = nil) -> ComposerAttachment? {
        if data.count > Self.maxBytesPerImage {
            lastError = "画像は1枚あたり4MiBまでです"
            return nil
        }
        if attachments.count >= Self.maxCount {
            lastError = "画像は4枚まで添付できます"
            return nil
        }
        if totalRawBytes + data.count > Self.maxTotalRawBytes {
            lastError = "画像は合計8MiBまでです"
            return nil
        }
        let number = ComposerImagePlaceholder.nextNumber(after: attachments.map(\.number))
        let attachment = ComposerAttachment(number: number, data: data, mediaType: mediaType, filename: filename)
        attachments.append(attachment)
        lastError = nil
        return attachment
    }

    /// 本文の編集で消えたプレースホルダに対応する添付を外す（task-4 契約。PM スタブは常に空）。
    /// 戻り値は実際に外した添付の番号。残る添付の番号は振り直さない。
    @discardableResult
    func removeAttachmentsMissing(fromOldText oldText: String, newText: String) -> [Int] {
        []
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
