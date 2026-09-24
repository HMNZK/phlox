#if os(macOS)
import AppKit
import SwiftUI

/// アプリアイコン。お知らせ・失敗の画面では注意の三角バッジを重ねる（09・11）。
public struct AppIconBadge: View {
    let showsCaution: Bool
    let size: CGFloat

    public init(showsCaution: Bool, size: CGFloat = 48) {
        self.showsCaution = showsCaution
        self.size = size
    }

    public var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if showsCaution {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: size * 20 / 48))
                        .offset(x: size / 12, y: size / 12)
                }
            }
            .accessibilityHidden(true)
    }
}
#endif
