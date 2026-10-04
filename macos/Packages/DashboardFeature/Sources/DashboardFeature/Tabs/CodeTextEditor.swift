import SwiftUI
import AppKit
import DesignSystem
import os

/// ファイルタブの編集欄（07 D4）。左に行番号（幅 28・右寄せ・淡色）。
/// SwiftUI の `TextEditor` には同期する行番号欄が無いので NSTextView を包む。
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var path = ""
    var blockEditID: UUID?
    var synchronizeBlockEdit: ((UUID, String) -> Void)?
    var commitBlockEdit: ((UUID) -> Bool)?
    var onBlockCommit: (() -> Void)?
    var registerBlockEditor: ((UUID, @escaping () -> Void, @escaping () -> Void) -> Void)?
    var requestBlockFocus = false

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        // 行番号の計算に NSLayoutManager を使うので TextKit 1 で作る。
        let textView = CurrentLineTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: blockEditID == nil ? 4 : 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = .monospacedSystemFont(ofSize: blockEditID == nil ? 11.5 : 11, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = blockEditID == nil ? 20 : 18
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        context.coordinator.updateBodyColor(textView)
        textView.string = text
        textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph,
                                          range: NSRange(location: 0, length: textView.string.utf16.count))
        textView.delegate = context.coordinator
        textView.onMarkedTextEnd = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.updateHighlights(textView, path: coordinator.highlights.path, debounce: true)
        }
        scrollView.documentView = textView
        scrollView.drawsBackground = true

        if blockEditID == nil {
            scrollView.verticalRulerView = LineNumberRuler(textView: textView)
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
        }
        // 組み立て後に登録する。登録時に撤去されても、取り付け済みの入力欄・行番号ごと外れる。
        configureBlockEdit(textView)
        context.coordinator.updateHighlights(textView, path: path)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CurrentLineTextView else { return }
        context.coordinator.text = $text
        configureBlockEdit(textView)
        Self.synchronizeText(text, with: textView, beforeReplacement: { context.coordinator.highlights.invalidate() })
        let background = NSColor(blockEditID == nil ? DSColor.background
            : DSColor.isDark ? DSColor.fieldBackground : DSColor.panelBackground)
        scrollView.backgroundColor = background
        textView.backgroundColor = background
        textView.insertionPointColor = NSColor(DSColor.textPrimary)
        textView.selectedTextAttributes[.backgroundColor] = NSColor(DSColor.textSelection)
        textView.needsDisplay = true
        if let ruler = scrollView.verticalRulerView as? LineNumberRuler {
            ruler.numberColor = NSColor(DSColor.textTertiary)
            ruler.backgroundColor = background
            ruler.needsDisplay = true
        }
        context.coordinator.updateHighlights(textView, path: path)
    }

    private func configureBlockEdit(_ textView: CurrentLineTextView) {
        textView.blockEditID = blockEditID
        textView.synchronizeBlockEdit = synchronizeBlockEdit
        textView.commitBlockEdit = commitBlockEdit
        textView.onBlockCommit = onBlockCommit
        if let id = blockEditID {
            registerBlockEditor?(id, { [weak textView] in textView?.synchronizeBlockEditText() },
                                 { [weak textView] in textView?.removeBlockEditor() })
        }
        if requestBlockFocus { textView.requestBlockFocusWhenAttached() }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.highlights.cancel()
        guard let textView = scrollView.documentView as? CurrentLineTextView else { return }
        textView.onMarkedTextEnd = nil
        textView.removeBlockEditor()
    }

    @discardableResult
    static func synchronizeText(_ text: String, with textView: NSTextView,
                                beforeReplacement: (() -> Void)? = nil) -> Bool {
        guard !textView.hasMarkedText(), !(textView.string as NSString).isEqual(to: text) else { return false }
        beforeReplacement?()
        textView.string = text
        return true
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let highlights = CodeSyntaxHighlights()
        private var baseThemeID: String?
        private weak var styledView: NSTextView?
        private let bodyColor = OSAllocatedUnfairLock(initialState: NSColor(DSColor.textPrimary))
        private lazy var dynamicBodyColor = NSColor(name: nil) { [bodyColor] _ in
            bodyColor.withLock { $0 }
        }
        init(text: Binding<String>) { self.text = text }

        func updateBodyColor(_ textView: NSTextView) {
            let themeID = ThemeStore.active.id
            if !textView.hasMarkedText(), styledView !== textView || baseThemeID != themeID {
                let selection = textView.selectedRanges
                let origin = textView.enclosingScrollView?.contentView.bounds.origin
                var typing = textView.typingAttributes
                bodyColor.withLock { $0 = NSColor(DSColor.textPrimary) }
                if styledView !== textView {
                    textView.undoManager?.disableUndoRegistration()
                    textView.textColor = dynamicBodyColor
                    textView.undoManager?.enableUndoRegistration()
                    styledView = textView
                } else {
                    textView.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(
                        location: 0, length: textView.textStorage?.length ?? 0))
                    textView.needsDisplay = true
                }
                if textView.selectedRanges != selection { textView.selectedRanges = selection }
                typing[.foregroundColor] = dynamicBodyColor
                if !NSDictionary(dictionary: textView.typingAttributes).isEqual(NSDictionary(dictionary: typing)) {
                    textView.typingAttributes = typing
                }
                if let origin, let clip = textView.enclosingScrollView?.contentView, clip.bounds.origin != origin {
                    clip.scroll(to: origin)
                }
                baseThemeID = themeID
            }
        }

        func updateHighlights(_ textView: NSTextView, path: String, debounce: Bool = false) {
            updateBodyColor(textView)
            highlights.update(textView, path: path, debounce: debounce)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            updateHighlights(textView, path: highlights.path, debounce: true)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            self.textView(textView, shouldChangeTextInRanges: [NSValue(range: affectedCharRange)],
                          replacementStrings: replacementString.map { [$0] })
        }

        func textView(_ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue],
                      replacementStrings: [String]?) -> Bool {
            if affectedRanges.count == 1 {
                highlights.recordEdit(affectedRanges[0].rangeValue,
                                      replacementLength: replacementStrings?.first?.utf16.count ?? 0)
            } else {
                highlights.invalidate()
            }
            return true
        }

    }
}

final class CurrentLineTextView: NSTextView {
    var onMarkedTextEnd: (() -> Void)?
    var blockEditID: UUID?
    var synchronizeBlockEdit: ((UUID, String) -> Void)?
    var commitBlockEdit: ((UUID) -> Bool)?
    var onBlockCommit: (() -> Void)?
    private var didRequestBlockFocus = false
    private var requestsBlockFocus = false
    private var isDismantlingBlockEdit = false
    private let blockUndoManager = UndoManager()
    private let sourceUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        blockEditID == nil ? sourceUndoManager : blockUndoManager
    }

    @objc func undo(_ sender: Any?) { undoManager?.undo() }
    @objc func redo(_ sender: Any?) { undoManager?.redo() }

    override func unmarkText() {
        super.unmarkText()
        onMarkedTextEnd?()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return undoManager?.canUndo == true }
        if item.action == #selector(redo(_:)) { return undoManager?.canRedo == true }
        return super.validateUserInterfaceItem(item)
    }

    /// IME の通知順に頼らず、確定した文字列を直接同期する。
    @discardableResult
    func synchronizeAndCommitBlockEdit() -> Bool {
        guard let id = blockEditID, !isDismantlingBlockEdit else { return true }
        synchronizeBlockEditText()
        guard commitBlockEdit?(id) == true else { return false }
        blockUndoManager.removeAllActions()
        blockEditID = nil
        onBlockCommit?()
        return true
    }

    func synchronizeBlockEditText() {
        guard let id = blockEditID else { return }
        if hasMarkedText() { unmarkText() }
        synchronizeBlockEdit?(id, string)
    }

    func dismantleBlockEdit() {
        isDismantlingBlockEdit = true
        blockUndoManager.removeAllActions()
        guard let id = blockEditID else { return }
        if hasMarkedText() { unmarkText() }
        synchronizeBlockEdit?(id, string)
        blockEditID = nil
    }

    func removeBlockEditor() {
        requestsBlockFocus = false
        onMarkedTextEnd = nil
        dismantleBlockEdit()
        delegate = nil
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        // 非表示にするだけでは読み上げに残るため、AppKit の木から入力欄を外す。
        let scrollView = enclosingScrollView
        scrollView?.verticalRulerView = nil
        scrollView?.documentView = nil
        removeFromSuperview()
        synchronizeBlockEdit = nil
        commitBlockEdit = nil
        onBlockCommit = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window != nil, newWindow == nil { dismantleBlockEdit() }
        super.viewWillMove(toWindow: newWindow)
    }

    func requestBlockFocusWhenAttached() {
        requestsBlockFocus = true
        focusBlockEditorIfAttached()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusBlockEditorIfAttached()
        if blockEditID == nil {
            // 本文の高さ確定で原点も動くので、取り付け後の原点へ合わせる。
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.blockEditID == nil,
                      let scrollView = self.enclosingScrollView else { return }
                scrollView.layoutSubtreeIfNeeded()
                scrollView.contentView.scroll(to: NSPoint(
                    x: self.frame.minX - scrollView.contentView.contentInsets.left, y: self.frame.minY))
            }
        }
    }

    private func focusBlockEditorIfAttached() {
        guard requestsBlockFocus, !didRequestBlockFocus, !isDismantlingBlockEdit,
              let id = blockEditID, let window else { return }
        // SwiftUI の取り付け処理の後に渡す。未取り付けの要求は消費しない。
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, self.blockEditID == id,
                  self.requestsBlockFocus, !self.didRequestBlockFocus, !self.isDismantlingBlockEdit else { return }
            self.didRequestBlockFocus = window.makeFirstResponder(self)
        }
    }

    override func resignFirstResponder() -> Bool {
        guard synchronizeAndCommitBlockEdit() else { return false }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if blockEditID != nil,
           event.keyCode == 53 || (event.keyCode == 36 && event.modifierFlags.contains(.command)) {
            if synchronizeAndCommitBlockEdit() { window?.makeFirstResponder(nil) }
            return
        }
        super.keyDown(with: event)
    }


}

/// 行番号欄。左 10・番号幅 28（右寄せ）・右 10（見本 PhloxAux のコード行）。
final class LineNumberRuler: NSRulerView {
    var numberColor: NSColor = .tertiaryLabelColor
    var backgroundColor: NSColor = .textBackgroundColor
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
        NotificationCenter.default.addObserver(
            self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func redraw() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        let font = textView.font ?? .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: numberColor]
        let nsString = textView.string as NSString
        let offset = convert(NSPoint.zero, from: textView).y
        let origin = textView.textContainerOrigin.y

        func drawNumber(_ number: Int, baseline: CGFloat) {
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = baseline + origin + offset - layoutManager.defaultBaselineOffset(for: font)
            label.draw(at: NSPoint(x: 10 + 28 - size.width, y: y), withAttributes: attributes)
        }

        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // ponytail: 表示範囲の先頭までの改行を毎回数える（O(n)）。巨大ファイルで重ければ行頭の索引を持つ。
        var number = 1
        nsString.enumerateSubstrings(in: NSRange(location: 0, length: characters.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            number += 1
        }
        if characters.location > 0, ![0x0A, 0x0D].contains(nsString.character(at: characters.location - 1)) { number -= 1 }

        var index = characters.location
        let end = NSMaxRange(characters)
        while index < end {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let lineGlyphs = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            guard lineGlyphs.length > 0 else { break }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineGlyphs.location, effectiveRange: nil)
            let empty = nsString.substring(with: lineRange).allSatisfy { $0.isNewline }
            let baseline = empty
                ? lineRect.maxY - layoutManager.defaultLineHeight(for: font) + layoutManager.defaultBaselineOffset(for: font)
                : lineRect.minY + layoutManager.location(forGlyphAt: lineGlyphs.location).y
            drawNumber(number, baseline: baseline)
            number += 1
            index = NSMaxRange(lineRange)
        }
        // 末尾が改行のとき、カーソルが置ける空の最終行にも番号を付ける。
        if index >= nsString.length, nsString.length == 0 || nsString.hasSuffix("\n") || nsString.hasSuffix("\r") {
            let extra = layoutManager.extraLineFragmentRect
            if extra.height > 0 {
                drawNumber(number, baseline: extra.maxY - layoutManager.defaultLineHeight(for: font)
                           + layoutManager.defaultBaselineOffset(for: font))
            }
        }
    }
}
