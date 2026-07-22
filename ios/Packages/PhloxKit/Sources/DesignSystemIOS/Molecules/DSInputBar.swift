import SwiftUI
import PhloxCore
#if os(iOS)
import PhotosUI
#endif

/// 添付ストリップの1件（確定時に生成済みの小さいプレビューのみ。フル解像度は ViewModel 側で保持）。
public struct DSAttachmentStripItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 本文の `[Image #N]` と対応する表示番号（1始まり）。task-3 契約。
    public let number: Int
    public let previewData: Data

    public init(id: UUID, number: Int = 1, previewData: Data) {
        self.id = id
        self.number = number
        self.previewData = previewData
    }
}

enum DSInputBarActionState: Equatable {
    case send(isEnabled: Bool)
    case stop
}

/// UTF-16 カーソル位置の正規化と公開タイミング（プラットフォーム非依存・白箱テスト対象）。
enum DSInputCursorMath {
    /// カーソルを `[0, textUTF16Count]` に収める。
    static func clampedCursorUTF16(_ cursorUTF16: Int, textUTF16Count: Int) -> Int {
        max(0, min(cursorUTF16, textUTF16Count))
    }

    /// 範囲外カーソルを正規化した値。範囲内なら `nil`。
    static func normalizedCursorIfNeeded(_ cursorUTF16: Int, textUTF16Count: Int) -> Int? {
        let clamped = clampedCursorUTF16(cursorUTF16, textUTF16Count: textUTF16Count)
        return clamped == cursorUTF16 ? nil : clamped
    }

    /// ユーザー操作由来の選択オフセットを binding へ反映すべきか（同値ループ防止）。
    static func shouldPublishSelectionOffset(_ selectionUTF16: Int, boundCursorUTF16: Int) -> Bool {
        selectionUTF16 != boundCursorUTF16
    }

    /// 外部 binding のカーソル変化を TextSelection へ押し戻すべきか。
    static func shouldPushSelection(cursorUTF16: Int, lastPushedCursorUTF16: Int) -> Bool {
        cursorUTF16 != lastPushedCursorUTF16
    }

    /// `String.Index` を UTF-16 オフセットへ変換する。`text` に属さない index では nil を返す
    /// （`String.Index.utf16Offset(in:)` は属さない index で trap するため直接使わない）。
    ///
    /// **`endIndex` を必ず受け付けること**: キャレットが本文末尾にあるのが最も普通の状態であり、
    /// `text.indices`（= startIndex..<endIndex）は endIndex を含まない。ここで弾くと
    /// 「末尾にカーソルがあるとカーソル位置が外部へ伝わらず、常に 0 のまま」になる。
    /// 選択範囲の両端が `text` に属するか。属さない（世代がずれた）範囲を
    /// SwiftUI が短くなった本文へ適用すると、範囲外アクセスでアプリが落ちる。
    static func isSelectionValid(_ range: Range<String.Index>, in text: String) -> Bool {
        utf16Offset(of: range.lowerBound, in: text) != nil
            && utf16Offset(of: range.upperBound, in: text) != nil
    }

    static func utf16Offset(of index: String.Index, in text: String) -> Int? {
        guard index == text.endIndex || text.indices.contains(index) else { return nil }
        return text.utf16.distance(from: text.utf16.startIndex, to: index)
    }
}

/// コンパクトなピル型のテキスト送信バー。画像添付・送信/停止を1列にまとめる。
public struct DSInputBar: View {
    static let minHeight: CGFloat = DSTouch.minSize
    static let sendButtonIconName = "arrow.up"
    static let stopButtonIconName = "stop.fill"
    static let maximumTextLineCount = 4
    /// テスト用契約（MoleculesTests · DS-AUDIT-4）。
    public static let usesFocusState = true
    public static let sendAccessibilityLabel = "送信"
    /// テスト用契約（task-3）: キーボード上の「完了」ツールバーを提供しない。
    public static let providesKeyboardDismissToolbar = false
    /// 入力欄内にモデルセレクタ差し込みスロットを持つ。空スロットはレイアウトへ影響しない。
    public static let providesInlineModelSelectorSlot = true
    public static let providesCardChrome = false
    public static let providesPillChrome = true
    public static let providesDragToDismiss = false
    public static let providesVoiceInput = false
    /// task-3 契約: 入力欄がカーソル位置を外部へ公開する（iOS 18 の TextSelection 経由）。
    public static let providesCursorAwareInput = true
    public static let usesNeutralFocusBorder = true
    public static let usesAccentFocusBorder = false
    public static let stopAccessibilityLabel = "停止"
    /// 旧契約名（task-3 刷新で `providesKeyboardDismissToolbar` へ移行）。
    @available(*, deprecated, renamed: "providesKeyboardDismissToolbar")
    public static let providesKeyboardDismissAffordance = providesKeyboardDismissToolbar
    @available(*, deprecated, message: "Keyboard dismiss toolbar removed in task-3 refresh")
    public static let keyboardDismissButtonLabel = "完了"
    static let sendButtonIconFont = DSFont.iconSend
    static let attachmentThumbnailSize: CGFloat = 56

    @Binding var text: String
    @Binding var cursorUTF16: Int
    let placeholder: String
    let isLoading: Bool
    let attachmentStrip: [DSAttachmentStripItem]
    let attachmentError: String?
    let contextLabel: String?
    let maxAttachments: Int
    let onAddAttachments: (([SendAttachment]) -> Void)?
    let onRemoveAttachment: ((Int) -> Void)?
    let isRunning: Bool
    let onStop: () -> Void
    let modelSelector: AnyView
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    #if os(iOS)
    @State private var textSelection: TextSelection?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    /// 外部 `cursorUTF16` を TextSelection へ反映中。ユーザー由来の `onChange` を抑止する。
    @State private var isApplyingExternalCursor = false
    /// 直近で押し戻した外部カーソル（ループ・世代ずれ検知用）。
    @State private var lastPushedCursorUTF16 = -1
    #endif

    public init(
        text: Binding<String>,
        cursorUTF16: Binding<Int> = .constant(0),
        placeholder: String,
        isLoading: Bool = false,
        attachmentStrip: [DSAttachmentStripItem] = [],
        attachmentError: String? = nil,
        contextLabel: String? = nil,
        maxAttachments: Int = 4,
        onAddAttachments: (([SendAttachment]) -> Void)? = nil,
        onRemoveAttachment: ((Int) -> Void)? = nil,
        isRunning: Bool = false,
        onStop: @escaping () -> Void = {},
        onSubmit: @escaping () -> Void
    ) {
        self.init(
            text: text,
            cursorUTF16: cursorUTF16,
            placeholder: placeholder,
            isLoading: isLoading,
            attachmentStrip: attachmentStrip,
            attachmentError: attachmentError,
            contextLabel: contextLabel,
            maxAttachments: maxAttachments,
            onAddAttachments: onAddAttachments,
            onRemoveAttachment: onRemoveAttachment,
            isRunning: isRunning,
            onStop: onStop,
            modelSelector: { EmptyView() },
            onSubmit: onSubmit
        )
    }

    public init<ModelSelector: View>(
        text: Binding<String>,
        cursorUTF16: Binding<Int> = .constant(0),
        placeholder: String,
        isLoading: Bool = false,
        attachmentStrip: [DSAttachmentStripItem] = [],
        attachmentError: String? = nil,
        contextLabel: String? = nil,
        maxAttachments: Int = 4,
        onAddAttachments: (([SendAttachment]) -> Void)? = nil,
        onRemoveAttachment: ((Int) -> Void)? = nil,
        isRunning: Bool = false,
        onStop: @escaping () -> Void = {},
        @ViewBuilder modelSelector: () -> ModelSelector,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self._cursorUTF16 = cursorUTF16
        self.placeholder = placeholder
        self.isLoading = isLoading
        self.attachmentStrip = attachmentStrip
        self.attachmentError = attachmentError
        self.contextLabel = contextLabel
        self.maxAttachments = maxAttachments
        self.onAddAttachments = onAddAttachments
        self.onRemoveAttachment = onRemoveAttachment
        self.isRunning = isRunning
        self.onStop = onStop
        self.modelSelector = AnyView(modelSelector())
        self.onSubmit = onSubmit
    }

    static func canSubmit(text: String, isLoading: Bool) -> Bool {
        DSSubmitBarLogic.canSubmit(text: text, isLoading: isLoading)
    }

    static func actionState(text: String, isLoading: Bool, isRunning: Bool) -> DSInputBarActionState {
        if isRunning { return .stop }
        return .send(isEnabled: canSubmit(text: text, isLoading: isLoading))
    }

    private var canSubmit: Bool { Self.canSubmit(text: text, isLoading: isLoading) }
    private var actionState: DSInputBarActionState {
        Self.actionState(text: text, isLoading: isLoading, isRunning: isRunning)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            if let attachmentError {
                Text(attachmentError)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.statusError)
            }
            if !attachmentStrip.isEmpty {
                attachmentStripView
            }

            if let contextLabel, !contextLabel.isEmpty {
                Label(contextLabel, systemImage: "arrow.triangle.branch")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
            }

            pillRow
        }
        #if os(iOS)
        .onChange(of: selectedPhotoItems) { _, items in
            guard onAddAttachments != nil else { return }
            Task { await importSelectedPhotos(items) }
        }
        #endif
    }

    private var pillRow: some View {
        HStack(alignment: .center, spacing: DSSpacing.s) {
            photoPickerButton

            inputTextField

            modelSelector
            actionButton
        }
        .padding(DSSpacing.xs)
        .background(DSColor.surfaceElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(pillBorderColor, lineWidth: 1))
    }

    @ViewBuilder
    private var inputTextField: some View {
        #if os(iOS)
        TextField(text: $text, selection: validatedTextSelection, axis: .vertical) {
            Text(placeholder)
                .foregroundStyle(DSColor.textTertiary)
        }
        .font(DSFont.body)
        .foregroundStyle(DSColor.textPrimary)
        .tint(DSColor.accent)
        .lineLimit(1...Self.maximumTextLineCount)
        .focused($isFocused)
        .accessibilityLabel(Text(placeholder))
        .onAppear { applyExternalCursorToSelection() }
        .onChange(of: textSelection) { _, selection in
            publishUserSelectionOffset(selection)
        }
        .onChange(of: cursorUTF16) { _, newCursor in
            guard DSInputCursorMath.shouldPushSelection(
                cursorUTF16: newCursor,
                lastPushedCursorUTF16: lastPushedCursorUTF16
            ) else { return }
            applyExternalCursorToSelection()
        }
        #else
        TextField(text: $text, axis: .vertical) {
            Text(placeholder)
                .foregroundStyle(DSColor.textTertiary)
        }
        .font(DSFont.body)
        .foregroundStyle(DSColor.textPrimary)
        .tint(DSColor.accent)
        .lineLimit(1...Self.maximumTextLineCount)
        .focused($isFocused)
        .accessibilityLabel(Text(placeholder))
        #endif
    }

    #if os(iOS)
    /// `textSelection` は `text` に属する `String.Index` を持つ。本文が外部から
    /// 書き換わる（プレースホルダの修復・送信時のクリア）と古い世代の index が残り、
    /// SwiftUI がそれを新しい短い本文へ適用しようとして落ちる。
    /// 読み出しの時点で検証し、世代がずれていたら選択を渡さない。
    private var validatedTextSelection: Binding<TextSelection?> {
        Binding(
            get: {
                guard let selection = textSelection,
                      case .selection(let range) = selection.indices,
                      DSInputCursorMath.isSelectionValid(range, in: text)
                else { return nil }
                return selection
            },
            set: { textSelection = $0 }
        )
    }

    private func applyExternalCursorToSelection() {
        isApplyingExternalCursor = true
        defer { isApplyingExternalCursor = false }

        let textUTF16Count = text.utf16.count
        if let normalized = DSInputCursorMath.normalizedCursorIfNeeded(
            cursorUTF16,
            textUTF16Count: textUTF16Count
        ) {
            cursorUTF16 = normalized
            return
        }

        let clamped = DSInputCursorMath.clampedCursorUTF16(cursorUTF16, textUTF16Count: textUTF16Count)
        lastPushedCursorUTF16 = clamped
        let index = String.Index(utf16Offset: clamped, in: text)
        textSelection = TextSelection(range: index..<index)
    }

    /// ユーザー操作由来の選択変化だけを `cursorUTF16` へ一方向反映する。
    private func publishUserSelectionOffset(_ selection: TextSelection?) {
        guard !isApplyingExternalCursor else { return }

        let capturedText = text
        Task { @MainActor in
            guard !isApplyingExternalCursor else { return }
            guard capturedText == text else { return }
            guard let offset = Self.selectionLeadingUTF16Offset(from: selection, in: text) else { return }
            guard DSInputCursorMath.shouldPublishSelectionOffset(offset, boundCursorUTF16: cursorUTF16) else {
                return
            }
            cursorUTF16 = offset
        }
    }

    /// `text` と同世代の `TextSelection` から先頭 UTF-16 オフセットを読む。
    /// 呼び出し側で世代ずれを弾いたあとにだけ使うこと。
    static func selectionLeadingUTF16Offset(from selection: TextSelection?, in text: String) -> Int? {
        guard let selection else { return nil }
        guard case .selection(let range) = selection.indices else { return nil }
        return DSInputCursorMath.utf16Offset(of: range.lowerBound, in: text)
    }
    #endif

    private var attachmentStripView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.s) {
                ForEach(attachmentStrip) { item in
                    attachmentThumbnail(item)
                }
            }
            .padding(.vertical, DSSpacing.xs)
        }
    }

    @ViewBuilder
    private func attachmentThumbnail(_ item: DSAttachmentStripItem) -> some View {
        let index = attachmentStrip.firstIndex(where: { $0.id == item.id }) ?? 0
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .topLeading) {
                attachmentPreview(for: item.previewData)
                    .frame(width: Self.attachmentThumbnailSize, height: Self.attachmentThumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                            .strokeBorder(DSColor.campCardBorder, lineWidth: 1)
                    )

                Text("#\(item.number)")
                    .font(DSFont.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textOnBrand)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, 2)
                    .background(DSColor.textSecondary.opacity(0.85), in: Capsule())
                    .padding(DSSpacing.xs)
                    .accessibilityLabel("添付\(item.number)")
            }

            if let onRemoveAttachment {
                Button {
                    onRemoveAttachment(index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textOnBrand, DSColor.textSecondary)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("添付を削除")
            }
        }
    }

    @ViewBuilder
    private func attachmentPreview(for previewData: Data) -> some View {
        #if os(iOS)
        if !previewData.isEmpty, let image = UIImage(data: previewData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            attachmentPlaceholder
        }
        #else
        attachmentPlaceholder
        #endif
    }

    private var attachmentPlaceholder: some View {
        ZStack {
            DSColor.fillSubtle
            Image(systemName: "photo")
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textTertiary)
        }
    }

    @ViewBuilder
    private var photoPickerButton: some View {
        #if os(iOS)
        let buttonSize = Self.minHeight
        if onAddAttachments != nil, attachmentStrip.count < maxAttachments {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: max(1, maxAttachments - attachmentStrip.count),
                matching: .images
            ) {
                Image(systemName: "plus")
                    .font(DSFont.iconSend)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(DSColor.fillSubtle, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("画像を添付")
        }
        #endif
    }

    #if os(iOS)
    private func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
        defer { selectedPhotoItems = [] }
        guard let onAddAttachments else { return }
        var imported: [SendAttachment] = []
        imported.reserveCapacity(items.count)
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            // mediaType は ViewModel 側でマジックバイト判定・再エンコードにより確定する。
            imported.append(SendAttachment(mediaType: "application/octet-stream", data: data))
        }
        guard !imported.isEmpty else { return }
        onAddAttachments(imported)
    }
    #endif

    private var pillBorderColor: Color {
        DSColor.campCardBorder
    }

    @ViewBuilder
    private var actionButton: some View {
        switch actionState {
        case .send:
            sendButton
        case .stop:
            stopButton
        }
    }

    private var sendButton: some View {
        Button(action: submit) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DSColor.textOnBrand)
                } else {
                    Image(systemName: Self.sendButtonIconName)
                        .font(Self.sendButtonIconFont)
                }
            }
            .foregroundStyle(DSColor.textOnBrand)
            .frame(width: Self.minHeight, height: Self.minHeight)
            .background(DSColor.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.45)
        .accessibilityLabel(Text(Self.sendAccessibilityLabel))
    }

    private var stopButton: some View {
        Button(action: stop) {
            Image(systemName: Self.stopButtonIconName)
                .font(Self.sendButtonIconFont)
                .foregroundStyle(DSColor.textOnBrand)
                .frame(width: Self.minHeight, height: Self.minHeight)
                .background(DSColor.statusError, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.stopAccessibilityLabel))
    }

    private func submit() {
        guard canSubmit else { return }
        onSubmit()
    }

    private func stop() {
        onStop()
    }
}

#if DEBUG
private struct DSInputBarPreviewHost: View {
    @State private var text = ""
    var body: some View {
        VStack(spacing: DSSpacing.m) {
            DSInputBar(text: $text, placeholder: "返信を入力…") {}
            DSInputBar(text: .constant("送信中のテキスト"), placeholder: "返信", isRunning: true) {}
        }
        .padding(DSSpacing.l)
    }
}

#Preview("DSInputBar") {
    DSInputBarPreviewHost()
}
#endif
