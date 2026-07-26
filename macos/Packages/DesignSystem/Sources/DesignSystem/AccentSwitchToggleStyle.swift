#if os(macOS)
import SwiftUI

/// ピル型スイッチ。ON=アクセント色トラック＋白ノブ右、OFF=灰トラック＋白ノブ左。
/// ON 色はテーマの accent を使うためカラースキーマ／テーマ切替に追従する。
/// クリック／キーボード操作を保つため Button をラベルに使う。
public struct AccentSwitchToggleStyle: ToggleStyle {
    private let trackWidth: CGFloat = 34
    private let trackHeight: CGFloat = 20
    private let knobInset: CGFloat = 2

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DSSpacing.m) {
            configuration.label
            Spacer(minLength: DSSpacing.m)
            Button {
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? DSColor.accent : DSColor.border)
                        .frame(width: trackWidth, height: trackHeight)
                    Circle()
                        .fill(.white)
                        .frame(width: trackHeight - knobInset * 2, height: trackHeight - knobInset * 2)
                        .padding(knobInset)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isOn)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
    }
}
#endif
