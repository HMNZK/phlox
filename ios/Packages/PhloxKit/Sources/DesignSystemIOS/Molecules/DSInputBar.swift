import SwiftUI
import PhloxCore
#if os(iOS)
import PhotosUI
#endif

/// 添付ストリップの1件（確定時に生成済みの小さいプレビューのみ。フル解像度は ViewModel 側で保持）。
public struct DSAttachmentStripItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let previewData: Data

    public init(id: UUID, previewData: Data) {
        self.id = id
        self.previewData = previewData
    }
}

enum DSInputBarActionState: Equatable {
    case send(isEnabled: Bool)
    case stop
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
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    #endif

    public init(
        text: Binding<String>,
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

            modelSelector
            actionButton
        }
        .padding(DSSpacing.xs)
        .background(DSColor.surfaceElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(pillBorderColor, lineWidth: 1))
    }

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
            attachmentPreview(for: item.previewData)
                .frame(width: Self.attachmentThumbnailSize, height: Self.attachmentThumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                        .strokeBorder(DSColor.campCardBorder, lineWidth: 1)
                )

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
