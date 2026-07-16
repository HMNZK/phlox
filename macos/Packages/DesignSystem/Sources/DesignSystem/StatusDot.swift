// このファイル全体は macOS 専用。実行中インジケータ（`RunningSpinner`）は、SwiftUI の
// repeat-forever 系アニメがメインスレッドを占有して埋め込みターミナル描画を飢餓させる回帰を避けるため、
// Core Animation 駆動の `NSViewRepresentable`（AppKit `NSView` + `QuartzCore`）で実装されている。
// これらは AppKit 依存で iOS には存在しない。コア DesignSystem ではステータス「語彙」は
// `StatusBadge`（色・ラベル・アイコン）として、視覚表現は `StatusCapsuleBadge`/`StatusLabel`
// （いずれもクロスプラットフォーム）として共有する。NSView ベースのドット表現を純 SwiftUI へ
// 置換すると新たな挙動・ロジックを持ち込むため、本タスク（ポータビリティのみ・ロジック不変）では
// macOS 専用のまま隔離し、iOS のステータス表示は DesignSystemIOS（E2-2 以降）で提供する。
// macOS ブランチの中身は隔離前と byte-equivalent（挙動不変）。
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
                RunningSpinner(color: StatusBadge.color(for: status))
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
    /// テスト専用フック。実行中スピナーの NSView を直接生成して検証できるようにする。
    /// `NSViewRepresentable.Context` は手で生成できないため、`makeNSView` を呼ばず
    /// `SpinnerView` を直接構築し、`makeNSView` と同じ初期化（レイヤー構築・アニメ追加・
    /// 色設定）を再現する。
    func makeSpinnerViewForTesting() -> RunningSpinner.SpinnerView {
        let view = RunningSpinner.SpinnerView()
        view.update(color: NSColor(StatusBadge.color(for: status)).cgColor)
        return view
    }
}
#endif

/// 実行中スピナー。回転を Core Animation（描画サーバー側）で回し、SwiftUI の
/// レイアウトループを毎フレーム起こさないようにする。SwiftUI の繰り返しアニメ
/// （repeat-forever 系）は NSHostingView を 60fps で再レイアウトさせ、アイドル時も
/// メインスレッドを占有して埋め込みターミナルの描画を飢餓させるため、
/// NSViewRepresentable へ置換している。
struct RunningSpinner: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> SpinnerView {
        let view = SpinnerView()
        view.update(color: NSColor(color).cgColor)
        return view
    }

    func updateNSView(_ nsView: SpinnerView, context: Context) {
        // 色（テーマ/ステータス変化）の更新のみ。アニメは再追加しない
        // （毎回追加するとリセット/多重化する）。
        nsView.update(color: NSColor(color).cgColor)
    }

    /// 部分円弧の描画と回転アニメを CAShapeLayer/CABasicAnimation で受け持つ NSView。
    final class SpinnerView: NSView {
        private let shape = CAShapeLayer()
        private static let arcKey = "phlox.spinner.rotation"

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            configureShape()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // StatusDot の 12x12 フレーム内に 11x11 で中央配置する。
        override var intrinsicContentSize: NSSize { NSSize(width: 11, height: 11) }

        private func configureShape() {
            shape.fillColor = NSColor.clear.cgColor
            shape.lineWidth = 2
            shape.lineCap = .round
            // 全周の円を path にし、strokeStart=0 / strokeEnd=0.72 で部分円弧にする。
            shape.strokeStart = 0
            shape.strokeEnd = 0.72
            // 中心回転のため anchorPoint を中央に。position は layout で中心へ置く。
            shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(shape)
            addRotationAnimation()
        }

        private func addRotationAnimation() {
            // delegate は使わない（retain cycle 回避）。
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = 2 * Double.pi
            rotation.duration = 0.8
            rotation.repeatCount = .infinity
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            rotation.isRemovedOnCompletion = false
            shape.add(rotation, forKey: Self.arcKey)
        }

        func update(color: CGColor) {
            shape.strokeColor = color
        }

        // レイヤーサイズ・位置の追従は layout が変わるときだけ行う。
        override func layout() {
            super.layout()
            let side: CGFloat = 11
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            shape.bounds = rect
            shape.position = CGPoint(x: bounds.midX, y: bounds.midY)
            // 旧 SwiftUI の Circle().stroke と同じ外径にするため、パスは bounds 全体に取り、
            // ストロークを縁の内外へ half-lineWidth ずつ跨がせる（外径 = bounds + lineWidth）。
            // レイヤーは masksToBounds=false なので、はみ出しは切られない。
            shape.path = CGPath(ellipseIn: rect, transform: nil)
        }
    }
}
#endif
