import SwiftUI
import AppKit
import AgentDomain
import CodexAppServerKit
import DesignSystem

struct ChatComposer: View {
    @Bindable var viewModel: ChatSessionViewModel
    @Binding var text: String
    let isRunning: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onInterrupt: () -> Void
    let controlsLayout: ComposerFooterLayout
    @State private var editorHeight: CGFloat = ComposerHeightBounds.single.min
    @State private var isComposing = false
    @State private var suggestionController: ComposerSuggestionController

    init(
        viewModel: ChatSessionViewModel,
        text: Binding<String>,
        isRunning: Bool,
        canSend: Bool,
        controlsLayout: ComposerFooterLayout = .standard,
        onSend: @escaping () -> Void,
        onInterrupt: @escaping () -> Void
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _text = text
        self.isRunning = isRunning
        self.canSend = canSend
        self.controlsLayout = controlsLayout
        self.onSend = onSend
        self.onInterrupt = onInterrupt
        _suggestionController = State(
            wrappedValue: ComposerSuggestionController.production(workingDirectory: viewModel.workspacePath)
        )
    }

    var body: some View {
        // パネル全体≈80px の要件（ADR 0046）: 間隔 xs・縦余白 s に圧縮（8+36+4+28+8=84）。
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if suggestionController.isPresented {
                ComposerSuggestionPopup(controller: suggestionController, onAccept: acceptSuggestionFromPopup)
                    .accessibilityIdentifier("ChatComposer.suggestions")
            }
            ComposerAttachmentStrip(
                store: viewModel.attachmentStore,
                layout: controlsLayout.settingsLayout,
                onRemove: removeAttachment
            )
            ZStack(alignment: .topLeading) {
                IMESafeTextView(
                    text: $text,
                    isComposing: $isComposing,
                    measuredHeight: $editorHeight,
                    minHeight: ComposerHeightBounds.single.min,
                    maxHeight: ComposerHeightBounds.single.max,
                    suggestionController: suggestionController,
                    onSubmit: onSend,
                    onPasteImageOutcome: addPastedImage,
                    attachedImageNumbers: { viewModel.attachmentStore.attachments.map(\.number) },
                    imagesForCopy: { viewModel.attachmentStore.imagesForCopy(numbers: $0) },
                    onEscape: { performChatEscape(viewModel) }
                )
                .frame(
                    minHeight: ComposerHeightBounds.single.min,
                    idealHeight: editorHeight,
                    maxHeight: ComposerHeightBounds.single.max
                )
                .accessibilityIdentifier("ChatComposer.input")

                if ComposerPlaceholderVisibility.shouldShowPlaceholder(text: text, isComposing: isComposing) {
                    Text("Ask Phlox anything...")
                        .font(ComposerPlaceholderMetrics.placeholderFont)
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .padding(.horizontal, ComposerPlaceholderMetrics.textInsets.width)
                        .padding(.vertical, ComposerPlaceholderMetrics.textInsets.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: editorHeight)
            .padding(.horizontal, DSSpacing.xs)

            ChatComposerFooter(
                viewModel: viewModel,
                layout: controlsLayout,
                isRunning: isRunning,
                canSubmit: canSubmit,
                onSend: onSend,
                onInterrupt: onInterrupt
            )
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        // フローティング配置（ADR 0065）で全幅の不透明下地が無くなったため、パネル本体は
        // chatBackground で不透明にしてから white 4% ティントを重ねる（背後のメッセージが
        // 透けない）。周囲余白帯は透明のまま＝スクロールバーは右下端まで視認できる。
        .background {
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .fill(DSColor.chatBackground)
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .fill(Color.white.opacity(0.04))
        }
        .overlay(
            // 入力欄パネルにごく薄いグレー味（white 4%）を足し、コンテンツ領域から少しだけ持ち上げて
            // 強調する。ストリップ・コンテンツは chatBackground のままで、境界はごく薄い枠のみ。
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(DSSpacing.m)
        .onChange(of: text) { oldValue, newValue in
            viewModel.syncAttachmentsWithDraftEdit(oldText: oldValue, newText: newValue)
        }
    }

    private var canSubmit: Bool {
        canSend && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachmentStore.attachments.isEmpty)
    }

    private func acceptSuggestionFromPopup(_ index: Int) {
        suggestionController.select(index)
        guard let replacement = suggestionController.acceptSelected() else { return }
        text = ComposerSuggestionTextReplacement.apply(replacement, to: text).text
    }

    private func addPastedImage(data: Data, mediaType: String) -> ComposerPasteImageOutcome {
        guard ComposerAttachmentCapability.supportsImageAttachments(agentRef: viewModel.agentRef) else {
            viewModel.attachmentStore.setError(ComposerAttachmentCapability.unsupportedImageMessage)
            return .unsupported
        }
        guard let attachment = viewModel.attachmentStore.addImage(data: data, mediaType: mediaType) else {
            return .rejected
        }
        return .attached(number: attachment.number)
    }

    private func removeAttachment(_ attachment: ComposerAttachment) {
        viewModel.attachmentStore.remove(id: attachment.id)
        text = ComposerImagePlaceholder.removing(number: attachment.number, from: text)
    }
}

struct ChatComposerFooter: View {
    @Bindable var viewModel: ChatSessionViewModel
    let layout: ComposerFooterLayout
    let isRunning: Bool
    let canSubmit: Bool
    let onSend: () -> Void
    let onInterrupt: () -> Void
    var accessibilityPrefix: String = "ChatComposer"
    var branchNameOverride: String?
    var branchIsCheckingOutOverride = false

    var body: some View {
        switch layout {
        case .minimal:
            minimalFooter
        case .standard, .compact:
            regularFooter
        }
    }

    private var regularFooter: some View {
        let settingsLayout = layout.settingsLayout
        return HStack(spacing: DSSpacing.s) {
            ComposerSettingsControlsView(
                viewModel: viewModel,
                layout: settingsLayout,
                side: .leading,
                accessibilityPrefix: accessibilityPrefix
            )
            ComposerContextIndicator(
                usage: viewModel.lastTurnUsage,
                workspacePath: viewModel.workspacePath,
                layout: settingsLayout == .compact ? .compact : .regular,
                branchNameOverride: branchNameOverride,
                branchIsCheckingOutOverride: branchIsCheckingOutOverride
            )
            .accessibilityIdentifier("\(accessibilityPrefix).contextIndicator")
            Spacer(minLength: DSSpacing.s)
            ComposerSettingsControlsView(
                viewModel: viewModel,
                layout: settingsLayout,
                side: .trailing,
                accessibilityPrefix: accessibilityPrefix
            )
            stopButton(size: settingsLayout == .compact ? 28 : 32)
            ComposerSendButton(
                canSubmit: canSubmit,
                action: onSend,
                accessibilityIdentifier: "\(accessibilityPrefix).sendButton"
            )
        }
    }

    private var minimalFooter: some View {
        HStack(spacing: DSSpacing.s) {
            ComposerAttachPlaceholder(
                viewModel: viewModel,
                layout: .compact,
                accessibilityIdentifier: "\(accessibilityPrefix).attachPlaceholder"
            )
            ComposerSettingsOverflowMenu(
                viewModel: viewModel,
                workspacePath: viewModel.workspacePath,
                accessibilityIdentifier: "\(accessibilityPrefix).overflowMenu"
            )
            Spacer(minLength: DSSpacing.s)
            stopButton(size: 28)
            ComposerSendButton(
                canSubmit: canSubmit,
                action: onSend,
                accessibilityIdentifier: "\(accessibilityPrefix).sendButton"
            )
        }
    }

    @ViewBuilder
    private func stopButton(size: CGFloat) -> some View {
        if isRunning {
            Button(action: onInterrupt) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(DSColor.statusError)
                    .frame(width: size, height: size)
            }
            .buttonStyle(HoverableIconButtonStyle())
            .accessibilityIdentifier("\(accessibilityPrefix).stopButton")
            .help("停止")
        }
    }
}

private struct ComposerSendButton: View {
    let canSubmit: Bool
    let action: () -> Void
    var accessibilityIdentifier: String = "ChatComposer.sendButton"
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canSubmit ? DSColor.chatBackground : DSColor.chatTextSecondary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .fill(canSubmit ? DSColor.chatAccent : Color.clear)
                    if isHovering && canSubmit {
                        RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .disabled(!canSubmit)
        .accessibilityIdentifier(accessibilityIdentifier)
        .help("送信")
    }
}

struct ComposerSuggestionPopup: View {
    @Bindable var controller: ComposerSuggestionController
    let onAccept: (Int) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: controller.candidates.count > ComposerSuggestionPopupMetrics.maxVisibleRows) {
            VStack(alignment: .leading, spacing: ComposerSuggestionPopupMetrics.rowSpacing) {
                ForEach(Array(controller.candidates.enumerated()), id: \.element.id) { index, candidate in
                    Button {
                        onAccept(index)
                    } label: {
                        HStack(spacing: DSSpacing.s) {
                            Image(systemName: candidate.kind == .slashCommand ? "terminal" : "doc.text")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(index == controller.selectedIndex ? DSColor.chatBackground : DSColor.chatTextSecondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.title)
                                    .font(DSFont.caption.weight(.semibold))
                                    .foregroundStyle(index == controller.selectedIndex ? DSColor.chatBackground : DSColor.chatTextPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let subtitle = candidate.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(index == controller.selectedIndex ? DSColor.chatBackground.opacity(0.72) : DSColor.chatTextSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: DSSpacing.s)
                        }
                        .padding(.horizontal, DSSpacing.s)
                        .frame(height: ComposerSuggestionPopupMetrics.rowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                                .fill(index == controller.selectedIndex ? DSColor.chatAccent : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            controller.select(index)
                        }
                    }
                }
            }
        }
        .padding(5)
        .frame(maxHeight: ComposerSuggestionPopupMetrics.maxContentHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.chatCard, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 8)
    }
}

private enum ComposerSuggestionPopupMetrics {
    static let maxVisibleRows = 8
    static let rowHeight: CGFloat = 34
    static let rowSpacing: CGFloat = 2
    static let outerPadding: CGFloat = 10

    static var maxContentHeight: CGFloat {
        outerPadding
            + (rowHeight * CGFloat(maxVisibleRows))
            + (rowSpacing * CGFloat(maxVisibleRows - 1))
    }
}

enum ComposerPlaceholderVisibility {
    static func shouldShowPlaceholder(text: String, isComposing: Bool) -> Bool {
        text.isEmpty && !isComposing
    }
}

struct IMESafeTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isComposing: Bool
    @Binding var measuredHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    var suggestionController: ComposerSuggestionController?
    let onSubmit: () -> Void
    var onPasteImage: ((Data, String) -> Bool)?
    var onPasteImageOutcome: ((Data, String) -> ComposerPasteImageOutcome)?
    /// 本文の `[Image #N]` をトークン単位で扱うための添付番号一覧（task-5）。
    var attachedImageNumbers: (() -> [Int])?
    /// 選択範囲に含まれる番号の画像（コピー時にクリップボードへ載せる。task-6）。
    var imagesForCopy: (([Int]) -> [(data: Data, mediaType: String)])?
    /// composer フォーカス時の esc 経路（task-9）。IME 変換中は呼ばれない。
    var onEscape: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.identifier = NSUserInterfaceItemIdentifier("ChatComposer.input")

        let textView = SubmitAwareTextView()
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onPasteImage = onPasteImage
        textView.onPasteImageOutcome = onPasteImageOutcome
        textView.attachedImageNumbers = attachedImageNumbers
        textView.imagesForCopy = imagesForCopy
        textView.onEscape = onEscape
        textView.suggestionController = suggestionController
        textView.onComposingChanged = { [coordinator = context.coordinator] isComposing, currentText in
            coordinator.setComposing(isComposing, currentText: currentText)
        }
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = ComposerPlaceholderMetrics.textNSFont
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = ComposerPlaceholderMetrics.textInsets
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.applyComposerHighlights()

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? SubmitAwareTextView else { return }
        textView.allowsUndo = true
        textView.onSubmit = onSubmit
        textView.onPasteImage = onPasteImage
        textView.onPasteImageOutcome = onPasteImageOutcome
        textView.attachedImageNumbers = attachedImageNumbers
        textView.imagesForCopy = imagesForCopy
        textView.onEscape = onEscape
        textView.suggestionController = suggestionController
        textView.onComposingChanged = { [coordinator = context.coordinator] isComposing, currentText in
            coordinator.setComposing(isComposing, currentText: currentText)
        }
        if !textView.hasMarkedText(), textView.string != text {
            textView.syncStringFromBinding(text)
            suggestionController?.update(text: text, cursorUTF16: min(textView.selectedRange().location, text.utf16.count))
        }
        // Bug A / ADR 0010: updateNSView は描画パスなので @State/@Binding を同期書込しない。
        // 差分ガード付き遅延書込は、実行時に再計算・再判定することで高々1回で固定点に収束する。
        if let nextHeight = context.coordinator.resolvedHeight(for: textView),
           ComposerHeightPolicy.shouldWrite(current: measuredHeight, next: nextHeight) {
            Task { @MainActor [weak textView, coordinator = context.coordinator] in
                guard let textView else { return }
                coordinator.recalculateHeight(for: textView)
            }
        }
        scrollView.hasVerticalScroller = measuredHeight >= maxHeight
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMESafeTextView

        init(_ parent: IMESafeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() {
                setComposing(true, currentText: textView.string)
                recalculateHeight(for: textView)
                return
            }
            parent.text = textView.string
            (textView as? SubmitAwareTextView)?.applyComposerHighlights()
            updateSuggestions(for: textView)
            recalculateHeight(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !textView.hasMarkedText() else { return }
            updateSuggestions(for: textView)
        }

        /// 選択が `[Image #N]` を分断しないように寄せる（task-7）。
        ///
        /// 個々のコマンド（shift+←、shift+↑、⌘shift+←、マウスドラッグ…）を列挙して
        /// override すると覆うべき集合が閉じないため、**選択変更の1箇所**でこの不変条件を守る。
        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
            toCharacterRange newSelectedCharRange: NSRange
        ) -> NSRange {
            guard !textView.hasMarkedText() else { return newSelectedCharRange }
            guard let numbers = (textView as? SubmitAwareTextView)?.attachedImageNumbers?(),
                  !numbers.isEmpty
            else { return newSelectedCharRange }

            let snapped = ComposerImagePlaceholder.snappedSelectionUTF16(
                from: oldSelectedCharRange.lowerBound..<oldSelectedCharRange.upperBound,
                to: newSelectedCharRange.lowerBound..<newSelectedCharRange.upperBound,
                in: textView.string,
                numbers: numbers
            )
            return NSRange(location: snapped.lowerBound, length: snapped.count)
        }

        func setComposing(_ isComposing: Bool, currentText: String) {
            if !isComposing, parent.text != currentText {
                parent.text = currentText
            }
            guard parent.isComposing != isComposing else { return }
            parent.isComposing = isComposing
        }

        func resolvedHeight(for textView: NSTextView) -> CGFloat? {
            guard let textContainer = textView.textContainer, let layoutManager = textView.layoutManager else { return nil }
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let insetHeight = textView.textContainerInset.height * 2
            return ComposerHeightPolicy.resolvedHeight(
                usedTextHeight: usedHeight,
                insetHeight: insetHeight,
                minHeight: parent.minHeight,
                maxHeight: parent.maxHeight
            )
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let nextHeight = resolvedHeight(for: textView) else { return }
            guard ComposerHeightPolicy.shouldWrite(current: parent.measuredHeight, next: nextHeight) else { return }
            parent.measuredHeight = nextHeight
        }

        private func updateSuggestions(for textView: NSTextView) {
            parent.suggestionController?.update(
                text: textView.string,
                cursorUTF16: textView.selectedRange().location
            )
        }
    }

    final class SubmitAwareTextView: NSTextView {
        var onSubmit: (() -> Void)?
        var onPasteImage: ((Data, String) -> Bool)?
        /// task-2 契約の PM スタブ。設定されていればこちらだけを呼び、結果に応じて
        /// カーソル位置へ `[Image #N]` を挿入する。nil なら従来の onPasteImage 経路。
        /// 受け入れテスト ComposerImageNumberingAcceptanceTests が凍結（シグネチャ変更禁止）。
        var onPasteImageOutcome: ((Data, String) -> ComposerPasteImageOutcome)?
        var onComposingChanged: ((Bool, String) -> Void)?
        var onEscape: (() -> Void)?
        var suggestionController: ComposerSuggestionController?
        /// 本文中のプレースホルダをトークン単位で扱うための、添付されている番号一覧。
        /// task-5 契約（受け入れテスト ComposerPlaceholderEditingAcceptanceTests が凍結）。
        var attachedImageNumbers: (() -> [Int])?
        /// 選択範囲に含まれる番号に対応する画像。コピー時にクリップボードへ載せる。
        /// task-6 契約（同上）。
        var imagesForCopy: (([Int]) -> [(data: Data, mediaType: String)])?

        // MARK: - トークン単位削除（task-5）

        override func deleteBackward(_ sender: Any?) {
            guard !deleteWholePlaceholder(direction: .backward) else { return }
            super.deleteBackward(sender)
        }

        override func deleteForward(_ sender: Any?) {
            guard !deleteWholePlaceholder(direction: .forward) else { return }
            super.deleteForward(sender)
        }

        /// カーソルがプレースホルダに掛かっていれば、トークンごとまとめて消す。
        /// 消したときだけ true（呼び出し元は通常の1文字削除を行わない）。
        @discardableResult
        func deleteWholePlaceholder(direction: ComposerImagePlaceholder.DeleteDirection) -> Bool {
            guard !hasMarkedText() else { return false }
            let selection = selectedRange()
            guard selection.length == 0 else { return false }
            guard let numbers = attachedImageNumbers?(), !numbers.isEmpty else { return false }
            guard let range = ComposerImagePlaceholder.deletionRangeUTF16(
                at: selection.location,
                in: string,
                numbers: numbers,
                direction: direction
            ) else { return false }

            let nsRange = NSRange(location: range.lowerBound, length: range.count)
            guard shouldChangeText(in: nsRange, replacementString: "") else { return true }
            textStorage?.replaceCharacters(in: nsRange, with: "")
            setSelectedRange(NSRange(location: range.lowerBound, length: 0))
            didChangeText()
            applyComposerHighlights()
            return true
        }

        // MARK: - 画像もコピーする（task-6）

        override func copy(_ sender: Any?) {
            guard writeSelectionWithImages(to: .general) else {
                super.copy(sender)
                return
            }
        }

        override func cut(_ sender: Any?) {
            // ⌘X も ⌘C と同じくクリップボードへ画像を載せる（載せた後に選択範囲を消す）。
            guard writeSelectionWithImages(to: .general) else {
                super.cut(sender)
                return
            }
            let selection = selectedRange()
            guard shouldChangeText(in: selection, replacementString: "") else { return }
            textStorage?.replaceCharacters(in: selection, with: "")
            setSelectedRange(NSRange(location: selection.location, length: 0))
            didChangeText()
            applyComposerHighlights()
        }

        /// 選択範囲にプレースホルダが含まれていれば、テキストと一緒に画像もクリップボードへ載せる。
        /// 載せたときだけ true（false なら呼び出し元が通常のコピーを行う）。
        @discardableResult
        func writeSelectionWithImages(to pasteboard: NSPasteboard) -> Bool {
            let selection = selectedRange()
            guard selection.length > 0, let numbers = attachedImageNumbers?(), !numbers.isEmpty else {
                return false
            }
            let selected = (string as NSString).substring(with: selection)
            let contained = numbers.filter { ComposerImagePlaceholder.contains(number: $0, in: selected) }
            guard !contained.isEmpty else { return false }
            let images = imagesForCopy?(contained) ?? []
            guard !images.isEmpty else { return false }

            // 1つ目の item にテキストと画像を両方載せる（貼り付け先が欲しい形を選べる）。
            // 2枚目以降は item を分ける（1つの item に同じ型は1つしか載らないため）。
            let encodable = images.compactMap { image -> (NSPasteboard.PasteboardType, Data)? in
                guard let type = Self.pasteboardType(forMediaType: image.mediaType) else { return nil }
                return (type, image.data)
            }
            // 1枚も載せられない形式なら通常のコピーに委ねる（テキストまで失わせない）。
            guard let firstImage = encodable.first else { return false }

            let first = NSPasteboardItem()
            first.setString(selected, forType: .string)
            first.setData(firstImage.1, forType: firstImage.0)
            var items: [NSPasteboardItem] = [first]
            for (type, data) in encodable.dropFirst() {
                let item = NSPasteboardItem()
                item.setData(data, forType: type)
                items.append(item)
            }

            pasteboard.clearContents()
            return pasteboard.writeObjects(items)
        }

        /// pasteboard が「この composer の添付を指すプレースホルダ入りテキスト」を持っているか。
        private func carriesOwnPlaceholderText(_ pasteboard: NSPasteboard) -> Bool {
            guard let numbers = attachedImageNumbers?(), !numbers.isEmpty,
                  let text = pasteboard.string(forType: .string)
            else { return false }
            return numbers.contains { ComposerImagePlaceholder.contains(number: $0, in: text) }
        }

        static func pasteboardType(forMediaType mediaType: String) -> NSPasteboard.PasteboardType? {
            switch mediaType {
            case "image/png": return NSPasteboard.PasteboardType("public.png")
            case "image/jpeg": return NSPasteboard.PasteboardType("public.jpeg")
            case "image/tiff": return NSPasteboard.PasteboardType("public.tiff")
            case "image/gif": return NSPasteboard.PasteboardType("com.compuserve.gif")
            case "image/webp": return NSPasteboard.PasteboardType("org.webmproject.webp")
            default: return nil
            }
        }

        override func keyDown(with event: NSEvent) {
            switch ComposerKeyRouting.action(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                isComposing: hasMarkedText(),
                suggestionsVisible: suggestionController?.isPresented == true
            ) {
            case .undo:
                undoManager?.undo()
            case .redo:
                undoManager?.redo()
            case .paste:
                paste(nil)
            case .submit:
                onSubmit?()
            case .insertNewline:
                insertNewline(nil)
            case .escape:
                onEscape?()
            case .moveSuggestionUp:
                suggestionController?.moveSelection(-1)
            case .moveSuggestionDown:
                suggestionController?.moveSelection(1)
            case .acceptSuggestion:
                if let replacement = suggestionController?.acceptSelected() {
                    applySuggestionReplacement(replacement)
                }
            case .dismissSuggestions:
                suggestionController?.dismiss()
            case .passToSystem:
                super.keyDown(with: event)
            }
        }

        func syncStringFromBinding(_ nextString: String) {
            guard string != nextString else { return }
            let currentSelection = selectedRange()
            let selectionLocation = min(currentSelection.location, nextString.utf16.count)
            let selectionLength = min(
                currentSelection.length,
                max(0, nextString.utf16.count - selectionLocation)
            )
            let manager = undoManager
            manager?.disableUndoRegistration()
            defer { manager?.enableUndoRegistration() }
            let attributedString = NSAttributedString(string: nextString, attributes: typingAttributes)
            if let textStorage {
                textStorage.setAttributedString(attributedString)
            } else {
                string = nextString
            }
            setSelectedRange(NSRange(location: selectionLocation, length: selectionLength))
            applyComposerHighlights()
            breakUndoCoalescing()
        }

        func applyComposerHighlights() {
            guard !hasMarkedText(), let textStorage else { return }

            let currentSelection = selectedRange()
            let defaultForegroundColor =
                typingAttributes[.foregroundColor] as? NSColor
                ?? textColor
                ?? NSColor.labelColor
            let manager = undoManager
            manager?.disableUndoRegistration()
            defer {
                setSelectedRange(currentSelection)
                manager?.enableUndoRegistration()
            }

            textStorage.beginEditing()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            if fullRange.length > 0 {
                textStorage.addAttribute(
                    .foregroundColor,
                    value: defaultForegroundColor,
                    range: fullRange
                )
            }
            // スラッシュコマンドと @参照 を別色にして種別を判別できるようにする。
            let slashColor = NSColor(DSColor.codeSyntaxKeyword)
            let referenceColor = NSColor(DSColor.codeSyntaxString)
            for span in ComposerHighlight.spans(in: string) {
                let range = NSRange(location: span.range.lowerBound, length: span.range.count)
                guard NSMaxRange(range) <= textStorage.length else { continue }
                let color = span.kind == .slashCommand ? slashColor : referenceColor
                textStorage.addAttribute(.foregroundColor, value: color, range: range)
            }
            textStorage.endEditing()

            var defaultTypingAttributes = typingAttributes
            defaultTypingAttributes[.foregroundColor] = defaultForegroundColor
            typingAttributes = defaultTypingAttributes
        }

        override func paste(_ sender: Any?) {
            if handlePaste(from: .general) {
                return
            }
            super.paste(sender)
        }

        // task-4 契約の PM スタブ。API 表面は受け入れテスト ChatFixTask4PasteAcceptanceTests が
        // 凍結している（シグネチャ変更禁止）。実装契約の正本: tasks/task-4.md
        // （paste(_:) の画像横取りロジックをこの検査可能な seam に移す。
        //   true = 画像として処理済み（テキストペースト抑止）/ false = 呼び出し側が通常ペースト）。
        func handlePaste(from pasteboard: NSPasteboard) -> Bool {
            // 自分でコピーした「テキスト＋画像」を貼り戻すときは、画像として横取りしない。
            // 横取りすると選択していた本文が丸ごと捨てられ、画像1枚だけが新規添付になる。
            if carriesOwnPlaceholderText(pasteboard) { return false }
            guard Self.shouldInterceptImagePaste(in: pasteboard),
                  let image = Self.imageData(from: pasteboard)
            else {
                return false
            }

            if let onPasteImageOutcome {
                switch onPasteImageOutcome(image.data, image.mediaType) {
                case .unsupported:
                    return false
                case .rejected:
                    return true
                case .attached(let number):
                    applyImagePlaceholderInsertion(number: number)
                    return true
                }
            }

            guard let onPasteImage else {
                return false
            }
            return onPasteImage(image.data, image.mediaType)
        }

        private func applyImagePlaceholderInsertion(number: Int) {
            if hasMarkedText() {
                unmarkText()
            }
            let applied = ComposerImagePlaceholder.inserting(
                number: number,
                into: string,
                cursorUTF16: selectedRange().location
            )
            guard applied.text != string else { return }
            let fullRange = NSRange(location: 0, length: string.utf16.count)
            guard shouldChangeText(in: fullRange, replacementString: applied.text) else { return }
            string = applied.text
            setSelectedRange(NSRange(location: applied.cursorUTF16, length: 0))
            didChangeText()
            applyComposerHighlights()
        }

        private func applySuggestionReplacement(_ replacement: SuggestionReplacement) {
            let applied = ComposerSuggestionTextReplacement.apply(replacement, to: string)
            guard applied.text != string else { return }
            let fullRange = NSRange(location: 0, length: string.utf16.count)
            guard shouldChangeText(in: fullRange, replacementString: applied.text) else { return }
            string = applied.text
            setSelectedRange(NSRange(location: applied.cursorUTF16, length: 0))
            didChangeText()
        }

        // IME の composing 状態は入力方式ごとに終了経路が異なる（候補確定で unmarkText を
        // 呼ぶ IME／insertText: だけで確定し didChangeText 経由になる IME 等）。取りこぼしを
        // 防ぐため setMarkedText/unmarkText/didChangeText の3経路すべてから composing 状態を
        // 再評価する（防御的な多重通知）。notifyComposingChanged → Coordinator.setComposing は
        // `hasMarkedText()` を単一の真実源とし、状態が変わらなければ binding を更新しない
        // べき等操作なので、多重呼び出しでも副作用はない。
        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            notifyComposingChanged()
        }

        override func unmarkText() {
            super.unmarkText()
            notifyComposingChanged()
        }

        override func didChangeText() {
            super.didChangeText()
            notifyComposingChanged()
        }

        private func notifyComposingChanged() {
            onComposingChanged?(hasMarkedText(), string)
        }

        private static func shouldInterceptImagePaste(in pasteboard: NSPasteboard) -> Bool {
            let availableTypes = Set((pasteboard.types ?? []).map(\.rawValue))
            return ComposerPastePolicy.shouldInterceptImagePaste(availableTypeIdentifiers: availableTypes)
        }

        private static func imageData(from pasteboard: NSPasteboard) -> (data: Data, mediaType: String)? {
            if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) {
                return (data, "image/png")
            }
            if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
                return (data, "image/jpeg")
            }
            guard let image = NSImage(pasteboard: pasteboard),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else {
                return nil
            }
            return (png, "image/png")
        }
    }
}

struct ComposerAttachmentStrip: View {
    @Bindable var store: ComposerAttachmentStore
    let layout: ComposerSettingsLayout
    let onRemove: (ComposerAttachment) -> Void

    private var chipHeight: CGFloat {
        layout == .compact ? 24 : 28
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if !store.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.xs) {
                        ForEach(store.attachments) { attachment in
                            ComposerAttachmentChip(
                                attachment: attachment,
                                chipHeight: chipHeight,
                                onRemove: { onRemove(attachment) }
                            )
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .accessibilityIdentifier("ChatComposer.attachments")
            }
            if let lastError = store.lastError {
                Text(lastError)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.statusError)
                    .lineLimit(2)
                    .accessibilityIdentifier("ChatComposer.attachmentError")
            }
        }
    }
}

private struct ComposerAttachmentChip: View {
    let attachment: ComposerAttachment
    let chipHeight: CGFloat
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "photo")
                .font(.system(size: 12, weight: .medium))
            Text(ComposerAttachmentChipPresentation.badge(for: attachment))
                .font(DSFont.caption.weight(.semibold))
                .accessibilityIdentifier("ChatComposer.attachmentBadge")
            Text(ComposerAttachmentChipPresentation.title(for: attachment))
                .font(DSFont.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("削除")
        }
        .foregroundStyle(DSColor.chatTextPrimary)
        .padding(.leading, DSSpacing.s)
        .padding(.trailing, 4)
        .frame(height: chipHeight)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                .fill(DSColor.chatCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}
