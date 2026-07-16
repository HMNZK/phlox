#if os(macOS)
import AppKit
import SwiftTerm

/// SwiftUI から埋め込んだターミナルがキーボード／IME フォーカスを受け取れるようにするコンテナ。
@MainActor
final class TerminalHostingView: NSView {
    /// 左端余白（DSSpacing.s と同値）。leading 制約のオフセットに使う。
    static let leftPadding: CGFloat = 8

    let terminalView: SwiftTerm.TerminalView

    init(terminalView: SwiftTerm.TerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leftPadding),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyOverlayScrollerStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(terminalView)
        super.mouseDown(with: event)
    }

    /// View がウィンドウに追加されたタイミングで自動的にターミナル本体へフォーカスを移す。
    /// SwiftUI から埋め込んだ場合、ユーザーが最初にクリックする前でもキー入力（IME 含む）を
    /// 受け取れるようにする。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.terminalView)
        }
    }

    /// フレームサイズが変わったとき（モード切替に伴う reparent・ウィンドウリサイズ・
    /// 初回レイアウト）に、SwiftTerm の incremental redraw が古いセルを残して
    /// 表示が重なる崩れを防ぐため、サイズ確定後に全行を再描画させる。
    /// バッファは保持し、描画レイヤーだけを full refresh で invalidate する非破壊処理。
    override func setFrameSize(_ newSize: NSSize) {
        let sizeChanged = newSize != frame.size
        super.setFrameSize(newSize)
        guard sizeChanged else { return }
        // SwiftTerm 側のグリッド再計算が終わってから再描画させるため次の runloop に回す。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let terminal = self.terminalView.getTerminal()
            terminal.refresh(startRow: 0, endRow: max(0, terminal.rows - 1))
            self.terminalView.needsDisplay = true
        }
    }

    /// SwiftTerm.TerminalView は内部に NSScroller を `.legacy` スタイル（常時表示・太め）で
    /// addSubview しており、public API から差し替えられない。グリッド表示時にすべてのタイルに
    /// 太いスクロールバーが出るのを避けるため、subviews から NSScroller を取り出して
    /// `.overlay` スタイル（スクロール時のみ薄く表示）に切り替える。
    /// 将来 SwiftTerm が複数の NSScroller を持つようになる可能性に備えて全件処理する。
    private func applyOverlayScrollerStyle() {
        for subview in terminalView.subviews {
            guard let scroller = subview as? NSScroller else { continue }
            scroller.scrollerStyle = .overlay
            scroller.knobStyle = .default
        }
    }
}
#endif
