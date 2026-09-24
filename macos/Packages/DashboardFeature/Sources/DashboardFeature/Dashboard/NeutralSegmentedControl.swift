import SwiftUI
import DesignSystem

/// 淡いトラックの上で選んだ側だけを面で示す切り替え（07 のインスペクタのタブ・差分 / 内容）。
/// システムの segmented はアクセント色で塗るため、色を対応待ちに取っておく方針に合わせて無彩色で描く。
struct NeutralSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]
    var fillsWidth = true
    var height: CGFloat = 22
    var fontSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isOn = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: fontSize))
                        .foregroundStyle(isOn ? DSColor.textPrimary : DSColor.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: height)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(DSColor.controlBackground)
                                    .shadow(color: .black.opacity(0.2), radius: 0.75, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(DSColor.segmentTrack, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
    }
}
