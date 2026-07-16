// このファイル全体は macOS 専用。ポインタ形状（`NSCursor` / `.pointerStyle`）と hover
// フィードバックは AppKit と macOS のポインティングデバイス前提の API に依存する。
// iOS（タッチ）には hover/カーソルの概念がないため、コア DesignSystem では提供せず、
// iOS 固有のインタラクションは将来の DesignSystemIOS（E2-2 以降）で別途定義する。
// macOS ブランチの中身は隔離前と byte-equivalent（挙動不変）。
#if os(macOS)
import SwiftUI
import AppKit

// クリック可能な要素に共通のインタラクション（ポインタ形状・ホバー/押下フィードバック）を
// 与えるための共有部品。アプリ全体でボタンの手触りを揃えるために DesignSystem に置く。

public extension View {
    /// ホバー中、ポインタを pointingHand（指差し）にする。クリック可能だと示したい要素に付与する。
    /// 視覚的なホバー演出は持たない（カーソルのみ）。
    /// macOS 15+ は `.pointerStyle(.link)` を使う。`.onHover` 内の `NSCursor.push/pop` は
    /// mouseMoved で arrow にリセットされ指差しが定着しない既知不具合があるため、SwiftUI 管理の
    /// pointerStyle に置き換える。macOS 14 は従来の push/pop へフォールバック。
    @ViewBuilder
    func pointingHandCursor() -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(.link)
        } else {
            modifier(PointingHandCursorModifier())
        }
    }

    /// 縦境界の左右リサイズカーソル。macOS 15+ は SwiftUI 管理の pointerStyle、14 は NSCursor フォールバック。
    @ViewBuilder
    func dsColumnResizeCursor() -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(.columnResize)
        } else {
            modifier(LegacyResizeCursorModifier())
        }
    }

    /// 有効/無効を受けるインタラクティブ要素用カーソル。有効時のみ指差しにする。
    /// macOS 15+ は `.pointerStyle`、14 は HoverCursorState ベースの push/pop。
    @ViewBuilder
    func dsInteractiveCursor(isEnabled: Bool) -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(isEnabled ? .link : nil)
        } else {
            modifier(LegacyInteractiveCursorModifier(isEnabled: isEnabled))
        }
    }

    /// Picker など ButtonStyle を適用できないクリック可能面に、共通のホバー面と pointingHand を付ける。
    func hoverableControlSurface(
        cornerRadius: CGFloat = DSRadius.m,
        baseFill: Color = .clear,
        hoverFill: Color = DSColor.fillSubtle,
        borderColor: Color = .clear,
        hoverBorderColor: Color = DSColor.fillSelected,
        isEnabled: Bool = true
    ) -> some View {
        modifier(HoverableControlSurfaceModifier(
            cornerRadius: cornerRadius,
            baseFill: baseFill,
            hoverFill: hoverFill,
            borderColor: borderColor,
            hoverBorderColor: hoverBorderColor,
            isEnabled: isEnabled
        ))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            // ホバー中に消えるとカーソルが pointingHand のまま残るため、明示的に戻す。
            .onDisappear {
                if isHovering { NSCursor.pop() }
            }
    }
}

/// macOS 14 フォールバック用。ホバー中は resizeLeftRight を push/pop で適用する。
private struct LegacyResizeCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering { NSCursor.pop() }
            }
    }
}

/// macOS 14 フォールバック用。有効時のみ HoverCursorState の push/pop で指差しにする。
private struct LegacyInteractiveCursorModifier: ViewModifier {
    let isEnabled: Bool
    @State private var cursor = HoverCursorState()

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                cursor.update(hovering: hovering, isEnabled: isEnabled).perform()
            }
            .onDisappear {
                cursor.finish().perform()
            }
    }
}

private struct HoverableControlSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let baseFill: Color
    let hoverFill: Color
    let borderColor: Color
    let hoverBorderColor: Color
    let isEnabled: Bool

    @State private var isHovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(isHovering ? hoverFill : baseFill))
            .overlay {
                shape.stroke(isHovering ? hoverBorderColor : borderColor, lineWidth: 1)
            }
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { hovering in
                isHovering = hovering && isEnabled
            }
            .dsInteractiveCursor(isEnabled: isEnabled)
    }
}

/// NSCursor のスタックは push/pop の対応が取れている前提のため、push していないのに pop すると
/// 祖先ビューが push したカーソルを誤って戻してしまう。その判定を View から切り離した純粋ロジック。
/// disabled なボタンへのホバーでは push しない（したがって離脱時も pop しない）。
struct HoverCursorState: Equatable {
    /// pointingHand を push 済みかどうか。
    private(set) var isPushed = false

    /// NSCursor へ適用すべき操作。
    enum Action: Equatable {
        case push
        case pop
        case none
    }

    /// ホバー/有効状態の変化に対して行うべきカーソル操作を返す。
    mutating func update(hovering: Bool, isEnabled: Bool) -> Action {
        let shouldShowPointingHand = hovering && isEnabled
        if shouldShowPointingHand, !isPushed {
            isPushed = true
            return .push
        }
        if !shouldShowPointingHand, isPushed {
            isPushed = false
            return .pop
        }
        return .none
    }

    /// ホバー中に View が消えるときの後始末。push 済みのときだけ pop する。
    mutating func finish() -> Action {
        guard isPushed else { return .none }
        isPushed = false
        return .pop
    }
}

extension HoverCursorState.Action {
    /// 決定済みの操作を NSCursor へ適用する。
    func perform() {
        switch self {
        case .push:
            NSCursor.pointingHand.push()
        case .pop:
            NSCursor.pop()
        case .none:
            break
        }
    }
}

/// アイコンボタン用スタイル。ホバー/押下で角丸ハイライト面を出し、ポインタを pointingHand にする。
/// ラベル（固定フレームのアイコン）の背後に面を敷くだけなのでレイアウトを変えない。
public struct HoverableIconButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .fill(fill)
                )
                .opacity(isEnabled ? 1 : 0.5)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering in
                    isHovering = hovering && isEnabled
                }
                .dsInteractiveCursor(isEnabled: isEnabled)
        }

        private var fill: Color {
            if configuration.isPressed { return DSColor.fillSelected }
            return isHovering ? DSColor.fillSubtle : .clear
        }
    }
}

/// ソフト塗りのテキストボタン用スタイル。常時は淡い面、ホバー/押下で面を明るくし、
/// ポインタを pointingHand にする。ラベル側に背景を持たせず、面はスタイルが一元管理する。
public struct HoverableSoftButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
        }

        var body: some View {
            configuration.label
                .background(shape.fill(fill))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.5)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering in
                    isHovering = hovering && isEnabled
                }
                .dsInteractiveCursor(isEnabled: isEnabled)
        }

        private var fill: Color {
            if configuration.isPressed || isHovering { return DSColor.fillSelected }
            return DSColor.fillSubtle
        }
    }
}

/// 既定で面を持たない行/ヘッダ/選択肢ボタン用スタイル。ホバー/押下時だけ面を強める。
public struct HoverableSurfaceButtonStyle: ButtonStyle {
    private let cornerRadius: CGFloat
    private let baseFill: Color
    private let hoverFill: Color
    private let pressedFill: Color
    private let borderColor: Color
    private let hoverBorderColor: Color

    public init(
        cornerRadius: CGFloat = DSRadius.m,
        baseFill: Color = .clear,
        hoverFill: Color = DSColor.fillSubtle,
        pressedFill: Color = DSColor.fillSelected,
        borderColor: Color = .clear,
        hoverBorderColor: Color = DSColor.fillSelected
    ) {
        self.cornerRadius = cornerRadius
        self.baseFill = baseFill
        self.hoverFill = hoverFill
        self.pressedFill = pressedFill
        self.borderColor = borderColor
        self.hoverBorderColor = hoverBorderColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledBody(
            configuration: configuration,
            cornerRadius: cornerRadius,
            baseFill: baseFill,
            hoverFill: hoverFill,
            pressedFill: pressedFill,
            borderColor: borderColor,
            hoverBorderColor: hoverBorderColor
        )
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        let baseFill: Color
        let hoverFill: Color
        let pressedFill: Color
        let borderColor: Color
        let hoverBorderColor: Color

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            configuration.label
                .background(shape.fill(fill))
                .overlay {
                    shape.stroke(isHovering ? hoverBorderColor : borderColor, lineWidth: 1)
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed && isEnabled ? 0.995 : 1)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering in
                    isHovering = hovering && isEnabled
                }
                .dsInteractiveCursor(isEnabled: isEnabled)
        }

        private var fill: Color {
            if configuration.isPressed { return pressedFill }
            return isHovering ? hoverFill : baseFill
        }
    }
}
#endif
