import SwiftUI
import AppKit
import DesignSystem
import os

/// ファイルタブの編集欄（07 D4）。左に行番号（42pt欄・右寄せ・淡色）、本文は56ptから。
/// SwiftUI の `TextEditor` には同期する行番号欄が無いので NSTextView を包む。
struct CodeTextEditor: NSViewRepresentable {
    // 本文をビュー構造の比較から外し、同期時には文書の最新値を読む。
    private let getText: () -> String
    private let setText: (String) -> Void
    var path = ""
    var bomByteCount = 0
    var isEditable = true
    var readOnlyText: ReadOnlyText?
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle
    var blockEditID: UUID?
    var synchronizeBlockEdit: ((UUID, String) -> Void)?
    var commitBlockEdit: ((UUID) -> Bool)?
    var onBlockCommit: (() -> Void)?
    var registerBlockEditor: ((UUID, @escaping () -> Void, @escaping () -> Void) -> Void)?
    var requestBlockFocus = false

    init(getText: @escaping () -> String, setText: @escaping (String) -> Void,
         path: String = "", bomByteCount: Int = 0, isEditable: Bool = true,
         readOnlyText: ReadOnlyText? = nil,
         blockEditID: UUID? = nil, synchronizeBlockEdit: ((UUID, String) -> Void)? = nil,
         commitBlockEdit: ((UUID) -> Bool)? = nil, onBlockCommit: (() -> Void)? = nil,
         registerBlockEditor: ((UUID, @escaping () -> Void, @escaping () -> Void) -> Void)? = nil,
         requestBlockFocus: Bool = false) {
        self.getText = getText
        self.setText = setText
        self.path = path
        self.bomByteCount = bomByteCount
        self.isEditable = isEditable
        self.readOnlyText = readOnlyText
        self.blockEditID = blockEditID
        self.synchronizeBlockEdit = synchronizeBlockEdit
        self.commitBlockEdit = commitBlockEdit
        self.onBlockCommit = onBlockCommit
        self.registerBlockEditor = registerBlockEditor
        self.requestBlockFocus = requestBlockFocus
    }

    func makeCoordinator() -> Coordinator { Coordinator(setText: setText) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        // 行番号の計算に NSLayoutManager を使うので TextKit 1 で作る。
        let textView = CurrentLineTextView(usingTextLayoutManager: false)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesFindBar = true
        textView.allowsUndo = isEditable
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        // 固定行高による4.5ptの差を引き、見本の1行目の文字位置に揃える。
        textView.textContainerInset = NSSize(width: blockEditID == nil ? 14 : 12, height: blockEditID == nil ? 3.5 : 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = blockEditID == nil ? 19.25 : 18
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        context.coordinator.updateBodyColor(textView)
        textView.string = context.coordinator.displayText(getText(), readOnlyText: readOnlyText,
                                                        locale: locale, bundle: localizationBundle)
        textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph,
                                          range: NSRange(location: 0, length: textView.string.utf16.count))
        textView.delegate = context.coordinator
        context.coordinator.bomByteCount = bomByteCount
        textView.onMarkedTextEnd = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.updateHighlights(textView, path: coordinator.path, debounce: true)
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
        context.coordinator.setText = setText
        context.coordinator.bomByteCount = bomByteCount
        if textView.isEditable != isEditable {
            textView.undoManager?.removeAllActions()
            textView.isEditable = isEditable
            textView.allowsUndo = isEditable
        }
        configureBlockEdit(textView)
        let display = context.coordinator.displayText(getText(), readOnlyText: readOnlyText,
                                                     locale: locale, bundle: localizationBundle)
        Self.synchronizeText(display, with: textView, beforeReplacement: { context.coordinator.highlights.invalidate() })
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
        // 破棄時の再描画要求で AppKit が非連続レイアウトの穴を全文埋め直して固まらないよう、先に本文と組版を切り離す。
        if let layoutManager = textView.layoutManager { textView.textStorage?.removeLayoutManager(layoutManager) }
        textView.removeBlockEditor()
    }

    @discardableResult
    static func synchronizeText(_ text: String, with textView: NSTextView,
                                beforeReplacement: (() -> Void)? = nil) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        let current = textView.string as NSString
        let incoming = text as NSString
        guard current !== incoming,
              current.length != incoming.length || !current.isEqual(incoming) else { return false }
        beforeReplacement?()
        textView.string = text
        return true
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var setText: (String) -> Void
        let highlights = CodeSyntaxHighlights()
        var bomByteCount = 0
        private(set) var path = ""
        private var highlightsEnabled = false
        private var displayedReadOnlyText: ReadOnlyText?
        private var displayLocale: Locale?
        private var displayBundle: Bundle?
        private var readOnlyDisplay: (text: String, markers: [NSRange]) = ("", [])
        private var baseThemeID: String?
        private weak var styledView: NSTextView?
        private let bodyColor = OSAllocatedUnfairLock(initialState: NSColor(DSColor.textPrimary))
        private lazy var dynamicBodyColor = NSColor(name: nil) { [bodyColor] _ in
            bodyColor.withLock { $0 }
        }
        init(setText: @escaping (String) -> Void) { self.setText = setText }

        func displayText(_ text: String, readOnlyText: ReadOnlyText?, locale: Locale, bundle: Bundle) -> String {
            guard let readOnlyText else {
                displayedReadOnlyText = nil
                readOnlyDisplay = ("", [])
                return text
            }
            if displayedReadOnlyText !== readOnlyText || displayLocale != locale || displayBundle !== bundle {
                readOnlyDisplay = readOnlyText.display(locale: locale, bundle: bundle)
                displayedReadOnlyText = readOnlyText
                displayLocale = locale
                displayBundle = bundle
            }
            return readOnlyDisplay.text
        }

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
            self.path = path
            updateBodyColor(textView)
            if textView.isEditable && WorkingTreeText.shouldHighlight(textView.string, bomByteCount: bomByteCount) {
                highlightsEnabled = true
                highlights.update(textView, path: path, debounce: debounce)
            } else {
                if highlightsEnabled { highlights.invalidate() }
                guard !textView.hasMarkedText() else { return }
                if highlightsEnabled {
                    textView.layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(
                        location: 0, length: textView.textStorage?.length ?? 0))
                    textView.undoManager?.disableUndoRegistration()
                    textView.font = .monospacedSystemFont(ofSize: (textView.typingAttributes[.font] as? NSFont)?.pointSize ?? 11,
                                                        weight: .regular)
                    textView.undoManager?.enableUndoRegistration()
                    highlightsEnabled = false
                }
                // フォント変更・貼付け・外部同期後も、非連続レイアウトの文字形を準備する。
                textView.layoutManager?.ensureGlyphs(forCharacterRange: NSRange(
                    location: 0, length: textView.textStorage?.length ?? 0))
                for range in readOnlyDisplay.markers {
                    textView.layoutManager?.addTemporaryAttribute(.foregroundColor,
                        value: NSColor(DSColor.textTertiary), forCharacterRange: range)
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, textView.isEditable else { return }
            setText(textView.string)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            updateHighlights(textView, path: path, debounce: true)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            self.textView(textView, shouldChangeTextInRanges: [NSValue(range: affectedCharRange)],
                          replacementStrings: replacementString.map { [$0] })
        }

        func textView(_ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue],
                      replacementStrings: [String]?) -> Bool {
            guard textView.isEditable else { return false }
            guard highlightsEnabled else { return true }
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
        guard isEditable else { return nil }
        return blockEditID == nil ? sourceUndoManager : blockUndoManager
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
        if blockEditID == nil, usesFindBar,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "f" {
            let action = NSMenuItem()
            action.tag = NSTextFinder.Action.showFindInterface.rawValue
            performTextFinderAction(action)
            return
        }
        if blockEditID != nil,
           event.keyCode == 53 || (event.keyCode == 36 && event.modifierFlags.contains(.command)) {
            if synchronizeAndCommitBlockEdit() { window?.makeFirstResponder(nil) }
            return
        }
        super.keyDown(with: event)
    }


}

/// 行番号欄は42pt、右寄せ。本文は14ptの間隔を空けた56ptから（見本3c）。
final class LineNumberRuler: NSRulerView {
    var numberColor: NSColor = .tertiaryLabelColor
    var backgroundColor: NSColor = .textBackgroundColor
    private weak var textView: NSTextView?
    private var lineStarts: [Int] = []

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 42
        NotificationCenter.default.addObserver(
            self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(contentsChanged(_:)), name: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func redraw() { needsDisplay = true }

    @objc private func contentsChanged(_ notification: Notification) {
        guard let storage = notification.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
        if !lineStarts.isEmpty {
            let text = storage.string as NSString
            let edited = storage.editedRange
            let delta = storage.changeInLength
            let first = max(0, upperBound(edited.location) - 2)
            let last = min(lineStarts.count, upperBound(NSMaxRange(edited) - delta) + 1)
            let start = lineStarts[first]
            let end = last < lineStarts.count ? lineStarts[last] + delta : text.length
            var replacement = [start]
            text.enumerateSubstrings(in: NSRange(location: start, length: end - start),
                                     options: [.byLines, .substringNotRequired]) { _, _, range, _ in
                if range.location > start { replacement.append(range.location) }
            }
            if last == lineStarts.count, hasTrailingNewline(text), replacement.last != text.length {
                replacement.append(text.length)
            }
            for index in last..<lineStarts.count { lineStarts[index] += delta }
            lineStarts.replaceSubrange(first..<last, with: replacement)
        }
        needsDisplay = true
    }

    private func lineNumber(at location: Int, in text: NSString) -> Int {
        if lineStarts.isEmpty {
            var starts = [0]
            text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, _, range, _ in
                if range.location > 0 { starts.append(range.location) }
            }
            if hasTrailingNewline(text) { starts.append(text.length) }
            lineStarts = starts
        }
        return upperBound(location)
    }

    private func upperBound(_ location: Int) -> Int {
        var lower = 0
        var upper = lineStarts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] <= location { lower = middle + 1 }
            else { upper = middle }
        }
        return lower
    }

    private func hasTrailingNewline(_ text: NSString) -> Bool {
        text.length > 0 && (CharacterSet.newlines as NSCharacterSet).characterIsMember(text.character(at: text.length - 1))
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: numberColor]
        let nsString = textView.string as NSString
        let offset = convert(NSPoint.zero, from: textView).y
        let origin = textView.textContainerOrigin.y

        func drawNumber(_ number: Int, baseline: CGFloat) {
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = baseline + origin + offset - layoutManager.defaultBaselineOffset(for: font)
            label.draw(at: NSPoint(x: ruleThickness - size.width, y: y), withAttributes: attributes)
        }

        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var number = lineNumber(at: characters.location, in: nsString)

        var index = characters.location
        let end = NSMaxRange(characters)
        while index < end {
            let start = lineStarts[number - 1]
            let stop = number < lineStarts.count ? lineStarts[number] : nsString.length
            let lineRange = NSRange(location: start, length: stop - start)
            let lineGlyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: lineRange.location, length: 1), actualCharacterRange: nil)
            guard lineGlyphs.length > 0 else { break }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineGlyphs.location, effectiveRange: nil)
            let empty = nsString.rangeOfCharacter(from: .newlines.inverted, options: [], range: lineRange).location == NSNotFound
            let baseline = empty
                ? lineRect.maxY - layoutManager.defaultLineHeight(for: font) + layoutManager.defaultBaselineOffset(for: font)
                : lineRect.minY + layoutManager.location(forGlyphAt: lineGlyphs.location).y
            drawNumber(number, baseline: baseline)
            number += 1
            index = NSMaxRange(lineRange)
        }
        // 末尾が改行のとき、カーソルが置ける空の最終行にも番号を付ける。
        if index >= nsString.length, nsString.length == 0 || hasTrailingNewline(nsString) {
            let extra = layoutManager.extraLineFragmentRect
            if extra.height > 0 {
                drawNumber(number, baseline: extra.maxY - layoutManager.defaultLineHeight(for: font)
                           + layoutManager.defaultBaselineOffset(for: font))
            }
        }
    }
}
