import SwiftUI
import DesignSystem
import PhloxCore

/// iOS 再設計用の色。共有 `DSColor` とは分け、ライト／ダークをアクティブテーマから解決する。
public enum IOSColor {
    private static var isLight: Bool { ThemeStore.active.preferredColorScheme == .light }

    public static var accent: Color { themed(0x1D1D1F, 0xF2F2F4) }
    public static var accentOnFill: Color { themed(0xFFFFFF, 0x000000) }
    public static var stop: Color { themed(0xD62F26, 0xE5483F) }
    public static var badge: Color { themed(0xD62F26, 0xE5483F) }
    public static var listRunningGlow: Color { themed(0xC9C9D0, 0xFFFFFF) }
    public static var toggleOn: Color { themed(0x34C759, 0x30B85A) }

    public static var text: TextColors { TextColors() }
    public static var status: StatusColors { StatusColors() }
    public static var bg: BackgroundColors { BackgroundColors() }

    public struct TextColors {
        public var primary: Color { IOSColor.themed(0x1D1D1F, 0xF2F2F4) }
        public var secondary: Color { IOSColor.themed(0x56565E, 0xAFAFB6) }
        public var tertiary: Color { IOSColor.themed(0x6B6B73, 0x9D9DA5) }
    }

    public struct StatusColors {
        public var approval: Color { IOSColor.statusColor(.approval) }
        public var approvalBackground: Color {
            IOSColor.isLight ? IOSColor.color(0xFFEBD6) : IOSColor.color(0xFF9F0A, opacity: 0.20)
        }
        public var question: Color { IOSColor.statusColor(.question) }
        public var questionBackground: Color {
            IOSColor.isLight ? IOSColor.color(0xE3EEFF) : IOSColor.color(0x0A84FF, opacity: 0.22)
        }
        public var error: Color { IOSColor.statusColor(.error) }
        public var errorBackground: Color {
            IOSColor.isLight ? IOSColor.color(0xFDE7E5) : IOSColor.color(0xFF453A, opacity: 0.18)
        }
        public var stalled: Color { IOSColor.statusColor(.stalled) }
        public var stalledBackground: Color {
            IOSColor.isLight ? IOSColor.color(0xF1ECFB) : IOSColor.color(0x9678E6, opacity: 0.20)
        }
        public var caution: Color { IOSColor.themed(0x8A5300, 0xF4BD68) }
        public var success: Color { IOSColor.statusColor(.done) }
        public var successBackground: Color {
            IOSColor.isLight ? IOSColor.color(0xE3F4E8) : IOSColor.color(0x34C759, opacity: 0.16)
        }
        public var neutral: Color { IOSColor.statusColor(.running) }
    }

    public struct BackgroundColors {
        public var base: Color { IOSColor.themed(0xF2F2F7, 0x000000) }
        public var scanner: Color { IOSColor.color(0x0E0E10) }
        public var appearancePreviewLight: Color { IOSColor.color(0xF0F0F5) }
        public var card: Color { IOSColor.themed(0xFFFFFF, 0x1C1C1E) }
        public var raised: Color { IOSColor.themed(0xE4E4EB, 0x2C2C30) }
        public var code: Color { IOSColor.themed(0xF7F6FA, 0x141416) }
        public var fill: Color {
            IOSColor.isLight ? IOSColor.color(0x767680, opacity: 0.12) : IOSColor.color(0x767680, opacity: 0.28)
        }
        public var separator: Color {
            IOSColor.isLight ? IOSColor.color(0x3C3C43, opacity: 0.18) : IOSColor.color(0x545458, opacity: 0.65)
        }
        public var glass: Color {
            IOSColor.isLight ? IOSColor.color(0xFFFFFF, opacity: 0.62) : IOSColor.color(0x26262A, opacity: 0.60)
        }
        public var bar: Color {
            IOSColor.isLight ? IOSColor.color(0xF9F9FB, opacity: 0.94) : IOSColor.color(0x161618, opacity: 0.94)
        }
        public var sheet: Color {
            IOSColor.isLight ? IOSColor.color(0xF2F2F7, opacity: 0.97) : IOSColor.color(0x1C1C1E, opacity: 0.97)
        }
        public var menu: Color {
            IOSColor.isLight ? IOSColor.color(0xFAFAFC, opacity: 0.94) : IOSColor.color(0x2C2C30, opacity: 0.94)
        }
        public var dim: Color { IOSColor.isLight ? Color.black.opacity(0.28) : Color.black.opacity(0.45) }
    }

    private static func themed(_ light: UInt32, _ dark: UInt32) -> Color {
        color(isLight ? light : dark)
    }

    private static func statusColor(_ state: SessionGlanceState) -> Color {
        color(state.foregroundHex(dark: !isLight))
    }

    private static func color(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
