// このファイル全体は macOS 専用。実行中インジケータ（`RunningBlinkDot`）は、SwiftUI の
// repeat-forever 系アニメがメインスレッドを占有して埋め込みターミナル描画を飢餓させる回帰を避けるため、
// Core Animation 駆動の `NSViewRepresentable`（AppKit `NSView` + `QuartzCore`）で実装されている。
// これらは AppKit 依存で iOS には存在しない。コア DesignSystem ではステータス「語彙」は
// `StatusBadge`（色・ラベル・アイコン）として、視覚表現は `StatusCapsuleBadge`/`StatusLabel`
// （いずれもクロスプラットフォーム）として共有する。NSView ベースのドット表現を純 SwiftUI へ
// 置換すると新たな挙動・ロジックを持ち込むため、本タスク（ポータビリティのみ・ロジック不変）では
// macOS 専用のまま隔離し、iOS のステータス表示は DesignSystemIOS（E2-2 以降）で提供する。
#if os(macOS)
import SwiftUI
import AppKit
import QuartzCore
import AgentDomain

public struct StatusDot: View {
    public let status: SessionStatus
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @Environment(\.locale) private var locale

    public init(status: SessionStatus) {
        self.status = status
    }

    private var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    public var body: some View {
        ZStack {
            if isRunning {
                // 実行中は静的な状態ドットと同径のドットを透明度で点滅させる。
                RunningBlinkDot(color: StatusBadge.color(for: status))
            } else {
                Circle()
                    .fill(StatusBadge.color(for: status))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 12, height: 12)
        .help(StatusBadge.helpText(for: status))
        .accessibilityLabel(StatusBadge.localizedLabel(for: status, locale: locale))
    }
}

#if DEBUG
extension StatusDot {
    /// テスト専用フック。実行中の点滅ドット NSView を直接生成して検証できるようにする。
    /// `NSViewRepresentable.Context` は手で生成できないため、`makeNSView` を呼ばず
    /// `BlinkDotView` を直接構築し、`makeNSView` と同じ初期化（レイヤー構築・アニメ追加・
    /// 色設定）を再現する。
    func makeBlinkDotViewForTesting() -> RunningBlinkDot.BlinkDotView {
        let view = RunningBlinkDot.BlinkDotView()
        view.update(color: NSColor(StatusBadge.color(for: status)).cgColor)
        return view
    }
}
#endif

/// 実行中の点滅ドット。透明度のパルスを Core Animation（描画サーバー側）で回し、SwiftUI の
/// レイアウトループを毎フレーム起こさないようにする。SwiftUI の繰り返しアニメ
/// （repeat-forever 系）は NSHostingView を 60fps で再レイアウトさせ、アイドル時も
/// メインスレッドを占有して埋め込みターミナルの描画を飢餓させるため、
/// NSViewRepresentable へ置換している。
struct RunningBlinkDot: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> BlinkDotView {
        let view = BlinkDotView()
        view.update(color: NSColor(color).cgColor)
        return view
    }

    func updateNSView(_ nsView: BlinkDotView, context: Context) {
        // 色（テーマ/ステータス変化）の更新のみ。アニメは再追加しない
        // （毎回追加するとリセット/多重化する）。
        nsView.update(color: NSColor(color).cgColor)
    }

    /// 塗りつぶした円ドットの描画と透明度の点滅アニメを CAShapeLayer/CABasicAnimation で受け持つ NSView。
    final class BlinkDotView: NSView {
        private let dot = CAShapeLayer()
        private static let blinkKey = "phlox.status.blink"

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            configureDot()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // StatusDot の 12x12 フレーム内に 8x8 で中央配置する（静的な状態ドットと同径）。
        override var intrinsicContentSize: NSSize { NSSize(width: 8, height: 8) }

        private func configureDot() {
            dot.strokeColor = NSColor.clear.cgColor
            // 中心を基準に配置。position は layout で中心へ置く。
            dot.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(dot)
            addBlinkAnimation()
        }

        private func addBlinkAnimation() {
            // delegate は使わない（retain cycle 回避）。透明度を 1.0⇄0.2 で往復させて点滅にする。
            let blink = CABasicAnimation(keyPath: "opacity")
            blink.fromValue = 1.0
            blink.toValue = 0.2
            blink.duration = 0.6
            blink.autoreverses = true
            blink.repeatCount = .infinity
            blink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            blink.isRemovedOnCompletion = false
            dot.add(blink, forKey: Self.blinkKey)
        }

        func update(color: CGColor) {
            dot.fillColor = color
        }

        // レイヤーサイズ・位置の追従は layout が変わるときだけ行う。
        override func layout() {
            super.layout()
            let side: CGFloat = 8
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            dot.bounds = rect
            dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
            dot.path = CGPath(ellipseIn: rect, transform: nil)
        }
    }
}
#endif
