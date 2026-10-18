import PhloxCore
import SwiftUI

/// ThemeStore を参照せず、拡張プロセスの端末外観だけで色を決める。
enum GlanceStyle {
    static func color(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static func card(dark: Bool) -> Color { color(dark ? 0x1C1C1E : 0xFFFFFF) }
    static func text(dark: Bool) -> Color { color(dark ? 0xF2F2F4 : 0x1D1D1F) }
    static func secondary(dark: Bool) -> Color { color(dark ? 0xAFAFB6 : 0x56565E) }
    static func ink(_ state: SessionGlanceState, dark: Bool, island: Bool = false) -> Color {
        color(state.foregroundHex(dark: dark, dynamicIsland: island))
    }
    static func fill(_ state: SessionGlanceState, dark: Bool) -> Color {
        let value = state.background(dark: dark)
        return color(value.hex, opacity: value.opacity)
    }
}

struct GlanceStatusSymbol: View {
    let state: SessionGlanceState

    var body: some View {
        Group {
            if let symbol = state.symbolName {
                Image(systemName: symbol).resizable().scaledToFit()
            } else {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.label)
    }
}
