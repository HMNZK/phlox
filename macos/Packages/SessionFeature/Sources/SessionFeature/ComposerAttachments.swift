import Foundation
import Observation
import AgentDomain
import DesignSystem

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

    /// 知らせの面の色（PhloxReply.dc.html の notice: 上限などは淡い赤、置き換えは中立）。
    /// 送られない画像の知らせは保存せず、いまのモデルから決める（`ComposerAttachmentCapability.imageNotice`）。
    enum NoticeTone { case error, neutral }

    private(set) var attachments: [ComposerAttachment] = []
    private(set) var lastError: String? { didSet { lastErrorTone = .error } }
    private(set) var lastErrorTone = NoticeTone.error

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
            lastError = "5 枚目は追加できません。画像は 1 枚 4MB・最大 4 枚・合計 8MB までです。"
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
        guard oldText != newText, !attachments.isEmpty else { return [] }
        let removedNumbers = ComposerImagePlaceholder.numbersRemoved(
            from: oldText,
            to: newText,
            among: attachments.map(\.number)
        )
        guard !removedNumbers.isEmpty else { return [] }
        let removeSet = Set(removedNumbers)
        attachments.removeAll { removeSet.contains($0.number) }
        return removedNumbers
    }

    /// 指定した番号に対応する画像を、添付順で返す（コピー時にクリップボードへ載せる。task-6 契約）。
    func imagesForCopy(numbers: [Int]) -> [(data: Data, mediaType: String)] {
        let wanted = Set(numbers)
        return attachments
            .filter { wanted.contains($0.number) }
            .map { ($0.data, $0.mediaType) }
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

    /// 送信済みメッセージへのリバート時に、保存済みの添付をそのまま復元する。
    func restore(_ attachments: [ComposerAttachment]) {
        self.attachments = attachments
        lastError = nil
    }

    func clearError() {
        lastError = nil
    }

    func setError(_ message: String, tone: NoticeTone = .error) {
        lastError = message
        lastErrorTone = tone
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
    /// 添付している画像がいまのモデルには送られないときの知らせ（05 R8 案 B。Codex の画像非対応モデル）。
    /// モデルを替えたら消えるように、保存せずに毎回決める。
    @MainActor
    static func imageNotice(_ viewModel: ChatSessionViewModel, locale: Locale) -> String? {
        guard viewModel.imageAttachmentSupport == .modelUnsupported, !viewModel.attachmentStore.attachments.isEmpty else { return nil }
        return modelUnsupportedNotice(viewModel, locale: locale)
    }

    @MainActor
    private static func modelUnsupportedNotice(_ viewModel: ChatSessionViewModel, locale: Locale) -> String {
        let model = viewModel.availableModels.first { $0.id == viewModel.selectedModel }?.displayName
            ?? viewModel.selectedModel
            ?? AppLocalizedString.string("このモデル", locale: locale)
        return String(format: AppLocalizedString.string("%@ は画像入力に対応していないため、この画像は送られません。モデルを切り替えると送れます。", locale: locale), model)
    }

    /// 画像を送れないエージェントで、＋から選んだ画像をファイルの参照にしたとき（05 R8 の Cursor）。
    static func fileReferenceNotice(agentRef: AgentRef, locale: Locale) -> String {
        String(format: AppLocalizedString.string("%@ では画像を添付できません。画像はファイルの参照（@パス）として挿入しました。", locale: locale), agentName(agentRef, locale: locale))
    }

    /// 画像を送れないエージェントで貼り付けたとき（貼り付けた画像にはパスが無いので参照にできない）。
    static func pasteUnsupportedNotice(agentRef: AgentRef, locale: Locale) -> String {
        String(format: AppLocalizedString.string("%@ では画像を貼り付けられません。画像ファイルは ＋ からファイルの参照（@パス）として挿入できます。", locale: locale), agentName(agentRef, locale: locale))
    }

    /// 貼り付けた画像（単体表示・グリッド共通）。送れないモデルでも添付し（知らせは `imageNotice`）、送れないエージェントでは断る。
    @MainActor
    static func addPastedImage(to viewModel: ChatSessionViewModel, data: Data, mediaType: String, locale: Locale) -> ComposerPasteImageOutcome {
        let support = viewModel.imageAttachmentSupport
        guard support != .agentUnsupported else {
            viewModel.attachmentStore.setError(pasteUnsupportedNotice(agentRef: viewModel.agentRef, locale: locale), tone: .neutral)
            return .unsupported
        }
        guard let attachment = viewModel.attachmentStore.addImage(data: data, mediaType: mediaType) else {
            return .rejected
        }
        return .attached(number: attachment.number)
    }

    private static func agentName(_ agentRef: AgentRef, locale: Locale) -> String {
        agentRef.builtinKind?.displayName ?? AppLocalizedString.string("このエージェント", locale: locale)
    }
}
