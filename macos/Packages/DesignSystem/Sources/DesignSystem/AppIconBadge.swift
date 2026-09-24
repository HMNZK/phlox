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
                    // 09: 右下に #E39A2D の三角と白い「!」（56pt のアイコンで 24×21、右 -4・下 -3）。
                    let scale = size / 56
                    CautionTriangle()
                        .fill(Color(red: 0xE3 / 255, green: 0x9A / 255, blue: 0x2D / 255))
                        .frame(width: 24 * scale, height: 21 * scale)
                        .overlay(alignment: .bottom) {
                            Text(verbatim: "!")
                                .font(.system(size: 12 * scale, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 4 * scale, y: 3 * scale)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct CautionTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
#endif
