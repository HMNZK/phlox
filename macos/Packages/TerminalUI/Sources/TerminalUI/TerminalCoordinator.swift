@preconcurrency import AppKit
@preconcurrency import Foundation
@preconcurrency import SwiftTerm

/// ターミナル(ANSI 16色＋背景/前景)のカラースキーマ。App 層が ThemeStore から構築して与える。
public struct TerminalPalette: Sendable {
    public struct Channel: Sendable {
        public let r: Int
        public let g: Int
        public let b: Int
        public init(_ r: Int, _ g: Int, _ b: Int) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    public let background: Channel
    public let foreground: Channel
    public let ansi: [Channel] // 16

    public init(background: Channel, foreground: Channel, ansi: [Channel]) {
        self.background = background
        self.foreground = foreground
        self.ansi = ansi
    }

    /// 既定（Phlox）フォールバック。App 層が activePalette を差し替えるまで使われる。
    public static let phloxDefault = TerminalPalette(
        background: Channel(14, 11, 23),
        foreground: Channel(214, 214, 214),
        ansi: [
            Channel(13, 11, 20), Channel(236, 72, 153), Channel(52, 211, 153), Channel(251, 191, 36),
            Channel(124, 140, 255), Channel(168, 85, 247), Channel(56, 189, 248), Channel(236, 233, 245),
            Channel(42, 36, 64), Channel(244, 114, 182), Channel(110, 231, 183), Channel(253, 230, 138),
            Channel(165, 180, 252), Channel(192, 132, 252), Channel(125, 211, 252), Channel(255, 255, 255),
        ]
    )
}

@MainActor
public final class TerminalCoordinator: NSObject, TerminalViewDelegate {
    /// terminalView の初期 frame。SwiftUI の AutoLayout で実 frame は親に追従するため
    /// この値は初回 layout 完了までの一時値に過ぎない。
    private static let initialFrame = NSRect(x: 0, y: 0, width: 800, height: 480)

    /// セッション寿命を通じて同じ SwiftTerm.TerminalView を保持する。
    /// SwiftUI 側がアタッチ／デタッチを繰り返しても feed されたバイト列が失われない。
    public let terminalView: SwiftTerm.TerminalView

    /// セッション寿命を通じて同じ TerminalHostingView を保持する。
    /// SwiftUI の NSViewRepresentable.makeNSView がモード切替などで再生成されても、
    /// 同じ hostingView を返すことで SwiftTerm.TerminalView の superview 切替を防ぎ、
    /// reparent に伴う描画崩れ・サイズ計算の不整合を避ける。
    /// 実体は TerminalUI 内部で生成し、外部からは NSView としてだけ公開する。
    public let hostingView: NSView

    public var onInput: (Data) -> Void = { _ in }
    public var onResize: (UInt16, UInt16) -> Void = { _, _ in }

    /// init 直後の SwiftTerm のグリッドサイズ。spawn 時に PTY を同じサイズで開くために使う。
    public var initialCols: UInt16 {
        UInt16(clamping: terminalView.getTerminal().cols)
    }
    public var initialRows: UInt16 {
        UInt16(clamping: terminalView.getTerminal().rows)
    }

    /// SwiftTerm が現在認識しているターミナルサイズ (最新)。
    public var currentCols: UInt16 {
        UInt16(clamping: terminalView.getTerminal().cols)
    }

    public var currentRows: UInt16 {
        UInt16(clamping: terminalView.getTerminal().rows)
    }

    /// 子アプリが bracketed paste mode (CSI ?2004h) を有効化しているか。
    /// 有効なら、プログラムからの入力注入を ESC[200~ … ESC[201~ で包んで
    /// 「ペースト」と明示でき、末尾の Enter がペースト本文と区別される。
    public var bracketedPasteMode: Bool {
        terminalView.getTerminal().bracketedPasteMode
    }

    public override convenience init() {
        // 既定はアプリ共通カラースキーマ (activePalette)。App 層が差し替える前に
        // 生成された Coordinator は phloxDefault で初期化される (従来挙動)。
        self.init(palette: Self.activePalette)
    }

    /// パレットを明示注入する designated init。
    /// グローバルな `activePalette` への初期化順序依存を避けたい場合 (テスト等) はこちらを使う。
    public init(palette: TerminalPalette) {
        // SwiftTerm の標準 TerminalView は macOS の `NSTextInputClient` のうち
        // markedText の描画が未実装なため、日本語 IME 変換中の未確定文字が見えない。
        // 拡張版 `IMETerminalView` でオーバーレイ表示を行う。
        let view = IMETerminalView(frame: Self.initialFrame)
        // 日本語 IME は Option キーを使うため Meta として奪わない。
        view.optionAsMetaKey = false
        // SwiftTerm の TerminalView は wantsLayer = true のレイヤーバックビュー。
        // グリッド(狭)→シングル(広) のようにサイズが拡大したとき、レイヤーの
        // バッキングが以前の描画を保持・引き伸ばし、新たに露出した右側に古い内容が
        // 残って表示が崩れる。
        // `.duringViewResize` はユーザー操作のライブリサイズ中しか再描画しないため、
        // プログラム的リサイズや、Claude Code のように同じ広い内容(表など)を
        // SIGWINCH ごとに各幅で再描画する TUI では、リサイズの合間にバッキングが
        // 再利用され旧フレームが各横位置に積み重なってゴースト化する。
        // `.onSetNeedsDisplay` は無効化(setFrameSize の needsDisplay 含む)のたびに
        // フレッシュに再描画させ、旧レイヤー内容の累積を断つ。
        view.layerContentsRedrawPolicy = .onSetNeedsDisplay
        // 文字色（ANSI 16 色）・背景・前景をアプリ共通のカラースキーマに合わせる。
        Self.apply(palette, to: view)
        view.useBrightColors = true
        self.terminalView = view
        self.hostingView = TerminalHostingView(terminalView: view)
        Self.applyHostBackground(palette, to: hostingView)
        super.init()
        self.terminalView.terminalDelegate = self
    }

    /// 現在のカラースキーマのターミナルパレット。App 層が起動時に ThemeStore から差し替える。
    /// 読み取りはこのクラス内では init() (既定値) と applyActivePalette() に限定し、
    /// パレットの適用処理自体は apply(_:to:) に集約してこのグローバル状態への依存を広げない。
    public static var activePalette: TerminalPalette = .phloxDefault

    /// パレット適用 3 点セット (ANSI 16 色・背景・前景)。init と applyActivePalette で共有する。
    private static func apply(_ palette: TerminalPalette, to view: SwiftTerm.TerminalView) {
        view.installColors(ansiSwiftTermColors(palette))
        view.nativeBackgroundColor = nsColor(palette.background)
        // SwiftTerm の既定前景色は中間グレー (Colors.defaultForeground ≈ 54% gray) で暗いため、
        // 色指定のない通常テキストが沈む。明るい前景色を明示指定して視認性を上げる。
        view.nativeForegroundColor = nsColor(palette.foreground)
    }

    /// 左 padding 帯を端末背景色で塗り、継ぎ目を出さない。
    private static func applyHostBackground(_ palette: TerminalPalette, to hostingView: NSView) {
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = nsColor(palette.background).cgColor
    }

    private static func nsColor(_ c: TerminalPalette.Channel) -> NSColor {
        NSColor(
            srgbRed: CGFloat(c.r) / 255.0,
            green: CGFloat(c.g) / 255.0,
            blue: CGFloat(c.b) / 255.0,
            alpha: 1.0
        )
    }

    /// パレットの ANSI 16 色を SwiftTerm.Color へ変換する。
    /// SwiftTerm.Color の init は UInt16 (0..65535) で受けるため 8bit 値を 257 倍する。
    private static func ansiSwiftTermColors(_ palette: TerminalPalette) -> [SwiftTerm.Color] {
        palette.ansi.map { ch in
            SwiftTerm.Color(
                red: UInt16(ch.r) * 257,
                green: UInt16(ch.g) * 257,
                blue: UInt16(ch.b) * 257
            )
        }
    }

    /// ターミナルの文字サイズを変更する。フォントファミリは現状の等幅フォントを維持する。
    public func applyFontSize(_ size: CGFloat) {
        let newFont = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        terminalView.font = newFont
    }

    /// 既存ターミナルへ現在の activePalette を再適用する（テーマのライブ切替用）。
    public func applyActivePalette() {
        Self.apply(Self.activePalette, to: terminalView)
        Self.applyHostBackground(Self.activePalette, to: hostingView)
        terminalView.needsDisplay = true
    }

    public func feed(_ data: Data) {
        terminalView.feed(byteArray: ArraySlice(data))
    }

    /// 現在の SwiftTerm viewport をプレーンテキスト化する。scrollback は含まない。
    public func visibleText() -> String {
        let terminal = terminalView.getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows
        var lines: [String] = []
        lines.reserveCapacity(rows)

        for row in 0..<rows {
            var line = ""
            line.reserveCapacity(cols)
            for col in 0..<cols {
                line.append(TerminalDump.displayCharacter(terminal.getCharacter(col: col, row: row)))
            }
            if let lastNonWhitespace = line.lastIndex(where: { !$0.isWhitespace }) {
                line = String(line[...lastNonWhitespace])
            } else {
                line = ""
            }
            lines.append(line)
        }

        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// scrollback を無効化し、通常バッファの reflow を止める。
    ///
    /// alternate screen を使わない TUI (Cursor/Codex 等) は、起動直後にターミナル幅が
    /// 変わるたびに各幅でプロンプトを再描画し、旧フレームが scrollback に積もってゴーストになる。
    /// scrollback 無効化により `Buffer.hasScrollback == false` → `isReflowEnabled == false` となり、
    /// 旧フレームが積まれる経路を断つ。
    public func disableScrollback() {
        terminalView.changeScrollback(nil)
    }

    /// セッション再起動 (restart) のために、SwiftTerm を「新規 TerminalCoordinator と同じ
    /// 初期状態」へ完全リセットする。
    ///
    /// 旧プロセス (Claude Code 等の Ink/React 系 TUI) は alternate screen buffer に入ったまま
    /// kill されるため terminal は alt buffer のまま残る (kill 前に outputTask を cancel するので
    /// 終了時の `?1049l` 復帰シーケンスは feed されない)。この状態で `buffer.clear()` だけ行っても
    /// buffer は alt のままで、再 spawn した新プロセスが送る `?1049h` が SwiftTerm の
    /// `activateAltBuffer` 早期 return (既に alt なら何もしない) に当たり、viewport 充填・refresh・
    /// bufferActivated が全てスキップされて画面が黒いまま戻らない。
    ///
    /// `ESC[?1049l` は alt screen を抜けて normal buffer へ戻し、同時に `activateNormalBuffer
    /// (clearAlt: true)` 経由で alt buffer の旧描画を完全に消す。続く `ESC c` (RIS) は scroll 領域・
    /// 各種モード・カーソルを初期状態へ戻す。`resetToInitialState()` 単体では alt buffer が
    /// `clearAlt: false` で消えず、差分描画する TUI で旧 cell が残る (初回 spawn は alt が空なので
    /// 起きない) ため、alt の明示クリアを先に行う。この 2 つで新規 TerminalCoordinator と同一の
    /// クリーンな状態になり、新プロセスが alt screen に入り直したとき初回 spawn と同一の空画面から
    /// 描画できる。インストール済みカラーパレットは保持される。
    public func resetBuffer() {
        terminalView.feed(byteArray: ArraySlice(Data("\u{1b}[?1049l\u{1b}c".utf8)))
        terminalView.needsDisplay = true
    }

    /// 現在の SwiftTerm viewport をファイルに dump する (デバッグ用)。
    /// 出力先: {outputDirectory}/terminal-dump-{sessionLabel}-{label}.txt
    /// (既定は ~/Library/Logs/Phlox)。整形とファイル書き込みは TerminalDump.write が担う。
    /// sessionLabel は呼び出し元 (SessionViewModel) が短 ID 等を渡す。
    /// 失敗してもアプリは継続する (try? + nil 許容)。
    ///
    /// MainActor 上で行うのは snapshot の取得だけに留める。O(cols×rows) の整形と
    /// 同期ファイル I/O は Task.detached へ逃がし、大グリッドでの描画・入力の瞬間的な
    /// 固まりを防ぐ (CellSnapshot は Sendable のため移送できる)。
    public func dumpForDebug(
        sessionLabel: String,
        label: String,
        ptyWinsize: (cols: Int, rows: Int)? = nil,
        outputDirectory: URL = TerminalDump.defaultOutputDirectory
    ) {
        let terminal = terminalView.getTerminal()
        let cells = TerminalDump.snapshot(terminal)
        let cursor = terminal.getCursorLocation()
        let cols = terminal.cols
        let rows = terminal.rows
        Task.detached(priority: .utility) {
            try? TerminalDump.write(
                cells,
                cols: cols,
                rows: rows,
                cursor: cursor,
                sessionLabel: sessionLabel,
                label: label,
                ptyWinsize: ptyWinsize,
                to: outputDirectory
            )
        }
    }

    // MARK: - TerminalViewDelegate

    public nonisolated func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        // SwiftTerm はレイアウト確定前に 0 や負値を渡してくることがあるため、
        // 異常値はスキップし、有効値のみ UInt16 にクランプして転送する。
        guard newCols > 0, newRows > 0 else { return }
        let cols = UInt16(clamping: newCols)
        let rows = UInt16(clamping: newRows)
        Task { @MainActor [weak self] in
            self?.onResize(cols, rows)
        }
    }

    public nonisolated func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

    public nonisolated func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

    public nonisolated func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        let inputData = Data(data)
        Task { @MainActor [weak self] in
            self?.onInput(inputData)
        }
    }

    public nonisolated func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

    public nonisolated func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}

    public nonisolated func bell(source: SwiftTerm.TerminalView) {}

    public nonisolated func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
}
